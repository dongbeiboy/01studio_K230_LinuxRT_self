/* Copyright (c) 2023, Canaan Bright Sight Co., Ltd
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
*/
#include <linux/clk.h>
#include <linux/component.h>
#include <linux/crc-ccitt.h>
#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/phy/phy-mipi-dphy.h>
#include <linux/phy/phy.h>
#include <linux/platform_device.h>
#include <linux/regulator/consumer.h>
#include <linux/reset.h>
#include <linux/slab.h>

#include <drm/drm_atomic_helper.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_panel.h>
#include <drm/drm_print.h>
#include <drm/drm_probe_helper.h>
#include <drm/drm_simple_kms_helper.h>
#include "canaan_dsi.h"
#include <video/mipi_display.h>

/* Synopsys DesignWare MIPI DSI Host Controller registers */
#define DSI_PWR_UP			0x04
#define  RESET				0
#define  POWERUP			BIT(0)

#define DSI_CLKMGR_CFG			0x08
#define  TO_CLK_DIVISION(d)		(((d) & 0xff) << 8)
#define  TX_ESC_CLK_DIVISION(d)	((d) & 0xff)

#define DSI_DPI_VCID			0x0c
#define DSI_DPI_COLOR_CODING		0x10
#define  DPI_COLOR_CODING_24BIT	0x5

#define DSI_DPI_CFG_POL			0x14
#define  COLORM_ACTIVE_LOW		BIT(4)
#define  SHUTD_ACTIVE_LOW		BIT(3)
#define  HSYNC_ACTIVE_LOW		BIT(2)
#define  VSYNC_ACTIVE_LOW		BIT(1)
#define  DATAEN_ACTIVE_LOW		BIT(0)

#define DSI_DPI_LP_CMD_TIM		0x18
#define  OUTVACT_LPCMD_TIME(p)		(((p) & 0xff) << 16)
#define  INVACT_LPCMD_TIME(p)		((p) & 0xff)

#define DSI_PCKHDL_CFG			0x2c
#define  CRC_RX_EN			BIT(4)
#define  ECC_RX_EN			BIT(3)
#define  BTA_EN				BIT(2)
#define  EOTP_RX_EN			BIT(1)
#define  EOTP_TX_EN			BIT(0)

#define DSI_GEN_VCID			0x30

#define DSI_MODE_CFG			0x34
#define  ENABLE_CMD_MODE		BIT(0)

#define DSI_VID_MODE_CFG		0x38
#define  VID_MODE_TYPE_BURST		0x2
#define  ENABLE_LOW_POWER_CMD		BIT(15)

#define DSI_VID_PKT_SIZE		0x3c
#define  VID_PKT_SIZE(p)		((p) & 0x3fff)

#define DSI_VID_HSA_TIME		0x48
#define DSI_VID_HBP_TIME		0x4c
#define DSI_VID_HLINE_TIME		0x50
#define DSI_VID_VSA_LINES		0x54
#define DSI_VID_VBP_LINES		0x58
#define DSI_VID_VFP_LINES		0x5c
#define DSI_VID_VACTIVE_LINES		0x60

#define DSI_CMD_MODE_CFG		0x68
#define  MAX_RD_PKT_SIZE_LP		BIT(24)
#define  DCS_LW_TX_LP			BIT(19)
#define  DCS_SR_0P_TX_LP		BIT(18)
#define  DCS_SW_1P_TX_LP		BIT(17)
#define  DCS_SW_0P_TX_LP		BIT(16)
#define  GEN_LW_TX_LP			BIT(14)
#define  GEN_SR_2P_TX_LP		BIT(13)
#define  GEN_SR_1P_TX_LP		BIT(12)
#define  GEN_SR_0P_TX_LP		BIT(11)
#define  GEN_SW_2P_TX_LP		BIT(10)
#define  GEN_SW_1P_TX_LP		BIT(9)
#define  GEN_SW_0P_TX_LP		BIT(8)

#define DSI_GEN_HDR			0x6c
#define DSI_GEN_PLD_DATA		0x70

#define DSI_CMD_PKT_STATUS		0x74
#define  GEN_RD_CMD_BUSY		BIT(6)
#define  GEN_PLD_R_FULL			BIT(5)
#define  GEN_PLD_R_EMPTY		BIT(4)
#define  GEN_PLD_W_FULL			BIT(3)
#define  GEN_PLD_W_EMPTY		BIT(2)
#define  GEN_CMD_FULL			BIT(1)
#define  GEN_CMD_EMPTY			BIT(0)

#define DSI_TO_CNT_CFG			0x78
#define DSI_LPCLK_CTRL			0x94
#define  AUTO_CLKLANE_CTRL		BIT(1)
#define  PHY_TXREQUESTCLKHS		BIT(0)

#define DSI_PHY_TMR_LPCLK_CFG		0x98
#define DSI_PHY_TMR_CFG			0x9c

struct dsi_hdr_scratch {
	u32 payload[2];
};

static inline void dsi_write(struct canaan_dsi *dsi, u32 reg, u32 val)
{
	writel(val, dsi->base + reg);
}

static inline u32 dsi_read(struct canaan_dsi *dsi, u32 reg)
{
	return readl(dsi->base + reg);
}

static void canaan_dsi_inst_abort(struct canaan_dsi *dsi)
{
	/* Reset DSI host controller */
	dsi_write(dsi, DSI_PWR_UP, RESET);
}

static int canaan_dsi_inst_wait_for_completion(struct canaan_dsi *dsi)
{
	u32 val;
	return readl_poll_timeout(dsi->base + DSI_CMD_PKT_STATUS, val,
				  !(val & GEN_CMD_FULL) && (val & GEN_CMD_EMPTY),
				  1000, 100000);
}

static int canaan_dsi_dcs_write_short(struct canaan_dsi *dsi,
				     const struct mipi_dsi_msg *msg)
{
	const u8 *tx_buf = msg->tx_buf;
	u32 val;
	int ret;

	/* Wait for FIFO not full */
	ret = readl_poll_timeout(dsi->base + DSI_CMD_PKT_STATUS, val,
				  !(val & GEN_CMD_FULL), 1000, 100000);
	if (ret) {
		dev_err(dsi->dev, "DSI DCS short write: FIFO full timeout\n");
		return ret;
	}

	/* Build DCS header:
	 * bits[23:16] = Data0 (DCS command byte)
	 * bits[15:8]  = Data1 (parameter 1, or 0 if not present)
	 * bits[7:6]   = Number of parameters (0, 1, or 2)
	 * bits[5:0]   = Data type (0x05 = DCS short write 0p, 0x15 = 1p, 0x17 = ???)
	 */
	val = tx_buf[0] << 16;  /* DCS command in Data0 */
	if (msg->tx_len > 1)
		val |= tx_buf[1] << 8;  /* parameter in Data1 */
	val |= ((msg->tx_len - 1) & 0x3) << 6;  /* num params in bits[7:6] */

	switch (msg->type) {
	case MIPI_DSI_DCS_SHORT_WRITE:
		val |= MIPI_DSI_DCS_SHORT_WRITE & 0x3f;  /* 0x05 */
		break;
	case MIPI_DSI_DCS_SHORT_WRITE_PARAM:
		val |= MIPI_DSI_DCS_SHORT_WRITE_PARAM & 0x3f;  /* 0x15 */
		break;
	case MIPI_DSI_GENERIC_SHORT_WRITE_2_PARAM:
		val |= MIPI_DSI_GENERIC_SHORT_WRITE_2_PARAM & 0x3f;
		break;
	default:
		dev_err(dsi->dev, "Unsupported short write type: %d\n", msg->type);
		return -EINVAL;
	}

	dsi_write(dsi, DSI_GEN_HDR, val);

	/* Wait for completion */
	return canaan_dsi_inst_wait_for_completion(dsi);
}

static int canaan_dsi_dcs_write_long(struct canaan_dsi *dsi,
				    const struct mipi_dsi_msg *msg)
{
	const u8 *tx_buf = msg->tx_buf;
	int len = msg->tx_len;
	u32 val;
	int ret;

	/* Wait for FIFO not full */
	ret = readl_poll_timeout(dsi->base + DSI_CMD_PKT_STATUS, val,
				  !(val & GEN_CMD_FULL), 1000, 100000);
	if (ret) {
		dev_err(dsi->dev, "DSI DCS long write: FIFO full timeout\n");
		return ret;
	}

	/* Write payload data to GEN_PLD_DATA first.
	 * GEN_PLD_DATA is a 32-bit FIFO, we write 4 bytes at a time.
	 */
	if (len >= 4) {
		u32 pld = (tx_buf[0] << 0) | (tx_buf[1] << 8) |
			  (tx_buf[2] << 16) | (tx_buf[3] << 24);
		dsi_write(dsi, DSI_GEN_PLD_DATA, pld);
		len -= 4;
		tx_buf += 4;
	}
	if (len >= 4) {
		u32 pld = (tx_buf[0] << 0) | (tx_buf[1] << 8) |
			  (tx_buf[2] << 16) | (tx_buf[3] << 24);
		dsi_write(dsi, DSI_GEN_PLD_DATA, pld);
		len -= 4;
		tx_buf += 4;
	}

	/* Now write the header. The header triggers the actual send.
	 * bits[23:16] = WC MSB (word count high)
	 * bits[15:8]  = WC LSB (word count low)
	 * bits[5:0]   = Data type (0x39 = DCS long write)
	 */
	val = (msg->tx_len << 8) & 0xffff00;  /* WC in bits[23:8] */
	val |= MIPI_DSI_DCS_LONG_WRITE & 0x3f;  /* 0x39 */

	dsi_write(dsi, DSI_GEN_HDR, val);

	/* Wait for completion */
	return canaan_dsi_inst_wait_for_completion(dsi);
}

static int canaan_dsi_dcs_read(struct canaan_dsi *dsi,
			      const struct mipi_dsi_msg *msg)
{
	u32 val;
	int ret;

	/* Wait for FIFO empty */
	ret = readl_poll_timeout(dsi->base + DSI_CMD_PKT_STATUS, val,
				  (val & GEN_CMD_EMPTY), 1000, 100000);
	if (ret) {
		dev_err(dsi->dev, "DSI DCS read: FIFO busy timeout\n");
		return ret;
	}

	/* Build DCS read header */
	val = ((const u8 *)msg->tx_buf)[0] << 16;  /* DCS command */
	val |= MIPI_DSI_DCS_READ & 0x3f;  /* 0x06 */

	dsi_write(dsi, DSI_GEN_HDR, val);

	/* Wait for read to complete */
	mdelay(10);

	/* Read back payload if available */
	val = dsi_read(dsi, DSI_GEN_PLD_DATA);
	if (msg->rx_buf && msg->rx_len > 0)
		((u8 *)msg->rx_buf)[0] = (u8)(val & 0xff);

	return 1;
}

static void canaan_dsi_encoder_enable(struct drm_encoder *encoder)
{
	struct canaan_dsi *dsi = encoder_to_canaan_dsi(encoder);
	struct drm_display_mode *mode;
	int hsync_len, hbp, hfp, h_act;
	int vsync_len, vbp, vfp, v_act;

	DRM_DEBUG_DRIVER("Enabling DSI output\n");

	/* Power up DSI */
	dsi_write(dsi, DSI_PWR_UP, POWERUP);

	/* Configure LP clock: TX escape clock division */
	dsi_write(dsi, DSI_LPCLK_CTRL, PHY_TXREQUESTCLKHS | AUTO_CLKLANE_CTRL);

	/* Configure packet handling: ECC, CRC, EoTp */
	dsi_write(dsi, DSI_PCKHDL_CFG, CRC_RX_EN | ECC_RX_EN | EOTP_TX_EN | EOTP_RX_EN | BTA_EN);

	/* Enable all LPDT modes for DCS commands */
	dsi_write(dsi, DSI_CMD_MODE_CFG,
		  DCS_LW_TX_LP | DCS_SR_0P_TX_LP | DCS_SW_1P_TX_LP |
		  DCS_SW_0P_TX_LP | GEN_LW_TX_LP | GEN_SR_2P_TX_LP |
		  GEN_SR_1P_TX_LP | GEN_SR_0P_TX_LP | GEN_SW_2P_TX_LP |
		  GEN_SW_1P_TX_LP | GEN_SW_0P_TX_LP);

	/* Configure DPI color coding: RGB888 */
	dsi_write(dsi, DSI_DPI_COLOR_CODING, DPI_COLOR_CODING_24BIT);
	dsi_write(dsi, DSI_DPI_LP_CMD_TIM, OUTVACT_LPCMD_TIME(4) | INVACT_LPCMD_TIME(4));

	/* Prepare panel (sends DCS init) */
	if (dsi->panel)
		drm_panel_prepare(dsi->panel);

	/* Configure video mode timing from connector's current mode */
	if (!list_empty(&dsi->connector.modes)) {
		mode = list_first_entry(&dsi->connector.modes,
					struct drm_display_mode, head);

		hsync_len = mode->hsync_end - mode->hsync_start;
		hbp = mode->htotal - mode->hsync_end;
		hfp = mode->hsync_start - mode->hdisplay;
		h_act = mode->hdisplay;

		vsync_len = mode->vsync_end - mode->vsync_start;
		vbp = mode->vtotal - mode->vsync_end;
		vfp = mode->vsync_start - mode->vdisplay;
		v_act = mode->vdisplay;

		/* Horizontal timing */
		dsi_write(dsi, DSI_VID_HSA_TIME, hsync_len);
		dsi_write(dsi, DSI_VID_HBP_TIME, hbp);
		dsi_write(dsi, DSI_VID_HLINE_TIME,
			  hsync_len + hbp + h_act + hfp);
		dsi_write(dsi, DSI_VID_VSA_LINES, vsync_len);
		dsi_write(dsi, DSI_VID_VBP_LINES, vbp);
		dsi_write(dsi, DSI_VID_VFP_LINES, vfp);
		dsi_write(dsi, DSI_VID_VACTIVE_LINES, v_act);

		/* Video packet size = hactive */
		dsi_write(dsi, DSI_VID_PKT_SIZE, VID_PKT_SIZE(h_act));

		dev_info(dsi->dev, "DSI video mode: %dx%d\n", h_act, v_act);
	}

	/* Set video mode: burst mode with LP commands */
	dsi_write(dsi, DSI_VID_MODE_CFG,
		  VID_MODE_TYPE_BURST | ENABLE_LOW_POWER_CMD);

	/* Switch to video mode */
	dsi_write(dsi, DSI_MODE_CFG, 0);  /* 0 = video mode */

	/* Enable the panel (backlight etc) */
	if (dsi->panel)
		drm_panel_enable(dsi->panel);
}

static void canaan_dsi_encoder_disable(struct drm_encoder *encoder)
{
	struct canaan_dsi *dsi = encoder_to_canaan_dsi(encoder);

	DRM_DEBUG_DRIVER("Disabling DSI output\n");

	if (dsi->panel) {
		drm_panel_disable(dsi->panel);
		drm_panel_unprepare(dsi->panel);
	}

	/* Put DSI in reset */
	dsi_write(dsi, DSI_PWR_UP, RESET);
}

static int canaan_dsi_get_modes(struct drm_connector *connector)
{
	struct canaan_dsi *dsi = connector_to_canaan_dsi(connector);

	return drm_panel_get_modes(dsi->panel, connector);
}

static const struct drm_connector_helper_funcs canaan_dsi_connector_helper_funcs = {
	.get_modes	= canaan_dsi_get_modes,
};

static enum drm_connector_status
canaan_dsi_connector_detect(struct drm_connector *connector, bool force)
{
	struct canaan_dsi *dsi = connector_to_canaan_dsi(connector);

	return dsi->panel ? connector_status_connected :
			    connector_status_disconnected;
}

static const struct drm_connector_funcs canaan_dsi_connector_funcs = {
	.detect			= canaan_dsi_connector_detect,
	.fill_modes		= drm_helper_probe_single_connector_modes,
	.destroy		= drm_connector_cleanup,
	.reset			= drm_atomic_helper_connector_reset,
	.atomic_duplicate_state	= drm_atomic_helper_connector_duplicate_state,
	.atomic_destroy_state	= drm_atomic_helper_connector_destroy_state,
};

static const struct drm_encoder_helper_funcs canaan_dsi_enc_helper_funcs = {
	.disable	= canaan_dsi_encoder_disable,
	.enable		= canaan_dsi_encoder_enable,
};

static int canaan_dsi_attach(struct mipi_dsi_host *host,
			    struct mipi_dsi_device *device)
{
	struct canaan_dsi *dsi = host_to_canaan_dsi(host);
	struct drm_panel *panel = of_drm_find_panel(device->dev.of_node);

	if (IS_ERR(panel))
		return PTR_ERR(panel);
	else
		dsi->connector.status = connector_status_connected;

	dsi->panel = panel;
	dsi->device = device;

	dev_info(host->dev, "Attached device %s\n", device->name);

	return 0;
}

static int canaan_dsi_detach(struct mipi_dsi_host *host,
			    struct mipi_dsi_device *device)
{
	struct canaan_dsi *dsi = host_to_canaan_dsi(host);

	dsi->panel = NULL;
	dsi->device = NULL;

	return 0;
}

static ssize_t canaan_dsi_transfer(struct mipi_dsi_host *host,
				  const struct mipi_dsi_msg *msg)
{
	struct canaan_dsi *dsi = host_to_canaan_dsi(host);
	int ret;

	ret = canaan_dsi_inst_wait_for_completion(dsi);
	if (ret < 0)
		canaan_dsi_inst_abort(dsi);

	switch (msg->type) {
	case MIPI_DSI_DCS_SHORT_WRITE:
	case MIPI_DSI_DCS_SHORT_WRITE_PARAM:
	case MIPI_DSI_GENERIC_SHORT_WRITE_2_PARAM:
		ret = canaan_dsi_dcs_write_short(dsi, msg);
		break;

	case MIPI_DSI_DCS_LONG_WRITE:
		ret = canaan_dsi_dcs_write_long(dsi, msg);
		break;

	case MIPI_DSI_DCS_READ:
		if (msg->rx_len == 1) {
			ret = canaan_dsi_dcs_read(dsi, msg);
			break;
		}
		fallthrough;

	default:
		ret = -EINVAL;
	}

	return ret;
}

static const struct mipi_dsi_host_ops canaan_dsi_host_ops = {
	.attach		= canaan_dsi_attach,
	.detach		= canaan_dsi_detach,
	.transfer	= canaan_dsi_transfer,
};


static int canaan_dsi_bind(struct device *dev, struct device *master,
			 void *data)
{
	struct drm_device *drm = data;
	struct canaan_dsi *dsi = dev_get_drvdata(dev);
	int ret;

	drm_encoder_helper_add(&dsi->encoder,
			       &canaan_dsi_enc_helper_funcs);
	ret = drm_simple_encoder_init(drm, &dsi->encoder,
				      DRM_MODE_ENCODER_DSI);
	if (ret) {
		dev_err(dsi->dev, "Couldn't initialise the DSI encoder\n");
		return ret;
	}
	dsi->encoder.possible_crtcs = BIT(0);

	drm_connector_helper_add(&dsi->connector,
				 &canaan_dsi_connector_helper_funcs);
	ret = drm_connector_init(drm, &dsi->connector,
				 &canaan_dsi_connector_funcs,
				 DRM_MODE_CONNECTOR_DSI);
	if (ret) {
		dev_err(dsi->dev,
			"Couldn't initialise the DSI connector\n");
		goto err_cleanup_connector;
	}

	drm_connector_attach_encoder(&dsi->connector, &dsi->encoder);

	dsi->drm = drm;

	return 0;

err_cleanup_connector:
	drm_encoder_cleanup(&dsi->encoder);
	return ret;
}

static void canaan_dsi_unbind(struct device *dev, struct device *master,
			    void *data)
{
	struct canaan_dsi *dsi = dev_get_drvdata(dev);

	dsi->drm = NULL;
}

static const struct component_ops canaan_dsi_ops = {
	.bind	= canaan_dsi_bind,
	.unbind	= canaan_dsi_unbind,
};

static int canaan_dsi_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct canaan_dsi *dsi;
	struct resource *res;
	int ret;

	dsi = devm_kzalloc(dev, sizeof(*dsi), GFP_KERNEL);
	if (!dsi)
		return -ENOMEM;
	dev_set_drvdata(dev, dsi);
	dsi->dev = dev;
	dsi->host.ops = &canaan_dsi_host_ops;
	dsi->host.dev = dev;

	/* Get and ioremap DSI registers */
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	dsi->base = devm_ioremap_resource(dev, res);
	if (IS_ERR(dsi->base)) {
		ret = PTR_ERR(dsi->base);
		dev_err(dev, "Unable to get DSI registers: %d\n", ret);
		return ret;
	}

	/* Get bus clock */
	dsi->bus_clk = devm_clk_get(dev, "pclk");
	if (IS_ERR(dsi->bus_clk)) {
		dev_err(dev, "Unable to get bus clock\n");
		return PTR_ERR(dsi->bus_clk);
	}

	ret = clk_prepare_enable(dsi->bus_clk);
	if (ret) {
		dev_err(dev, "Failed to enable bus clock: %d\n", ret);
		return ret;
	}

	/* DSI reset - put in reset then release */
	dsi_write(dsi, DSI_PWR_UP, RESET);
	usleep_range(1000, 2000);

	ret = mipi_dsi_host_register(&dsi->host);
	if (ret) {
		dev_err(dev, "Couldn't register MIPI-DSI host\n");
		goto err_disable_clk;
	}

	ret = component_add(&pdev->dev, &canaan_dsi_ops);
	if (ret) {
		dev_err(dev, "Couldn't register our component\n");
		goto err_remove_dsi_host;
	}

	dev_info(dev, "Canaan K230 DSI probed at 0x%pa\n", &res->start);
	return 0;

err_remove_dsi_host:
	mipi_dsi_host_unregister(&dsi->host);
err_disable_clk:
	clk_disable_unprepare(dsi->bus_clk);
	return ret;
}

static int canaan_dsi_remove(struct platform_device *pdev)
{
	struct canaan_dsi *dsi = dev_get_drvdata(&pdev->dev);

	component_del(&pdev->dev, &canaan_dsi_ops);
	mipi_dsi_host_unregister(&dsi->host);
	clk_disable_unprepare(dsi->bus_clk);

	return 0;
}

static const struct of_device_id canaan_dsi_of_table[] = {
	{ .compatible = "canaan,k230-mipi-dsi" },
	{ }
};
MODULE_DEVICE_TABLE(of, canaan_dsi_of_table);

struct platform_driver canaan_dsi_driver = {
	.probe		= canaan_dsi_probe,
	.remove		= canaan_dsi_remove,
	.driver		= {
		.name		= "canaan-mipi-dsi",
		.of_match_table	= canaan_dsi_of_table,
	},
};


MODULE_AUTHOR("");
MODULE_DESCRIPTION("Canaan K230 DSI Driver");
MODULE_LICENSE("GPL");
