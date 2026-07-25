// SPDX-License-Identifier: GPL-2.0-only
/*
 * Canaan Universal MIPI DSI Panel Driver
 * Supports: HX8399 (800x480 and 1080x1920 variants)
 *
 * Copyright (C) 2022-2024, Canaan Bright Sight Co., Ltd
 */

#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/fb.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of_device.h>

#include <linux/gpio/consumer.h>
#include <linux/regulator/consumer.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

#include <video/mipi_display.h>
#include <video/of_videomode.h>
#include <video/videomode.h>

/* HX8399 DCS initialization sequence from big-core connector driver */
static const u8 hx8399_init_seq[] = {
	/* Extend command set */
	0xB9, 0xFF, 0x83, 0x99,
	0xD2, 0xAA,
	/* DSI control */
	0xB1, 0x02, 0x04, 0x71, 0x91, 0x01, 0x32, 0x33,
	0x11, 0x11, 0xAB, 0x4D, 0x56, 0x73, 0x02, 0x02,
	/* Power control */
	0xB2, 0x00, 0x80, 0x80, 0xAE, 0x05, 0x07, 0x5A,
	0x11, 0x00, 0x00, 0x10, 0x1E, 0x70, 0x03, 0xD4,
	/* VCOM */
	0xB4, 0x00, 0xFF, 0x02, 0xC0, 0x02, 0xC0, 0x00,
	0x00, 0x08, 0x00, 0x04, 0x06, 0x00, 0x32, 0x04,
	0x0A, 0x08, 0x21, 0x03, 0x01, 0x00, 0x0F, 0xB8,
	0x8B, 0x02, 0xC0, 0x02, 0xC0, 0x00, 0x00, 0x08,
	0x00, 0x04, 0x06, 0x00, 0x32, 0x04, 0x0A, 0x08,
	0x01, 0x00, 0x0F, 0xB8, 0x01,
	/* GIP (Gate In Panel) */
	0xD3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06,
	0x00, 0x00, 0x10, 0x04, 0x00, 0x04, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x01, 0x00, 0x05, 0x05, 0x07, 0x00, 0x00, 0x00,
	0x05, 0x40,
	/* Panel positive gamma */
	0xD5, 0x18, 0x18, 0x19, 0x19, 0x18, 0x18, 0x21,
	0x20, 0x01, 0x00, 0x07, 0x06, 0x05, 0x04, 0x03,
	0x02, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x2F,
	0x2F, 0x30, 0x30, 0x31, 0x31, 0x18, 0x18, 0x18,
	0x18,
	/* Panel negative gamma */
	0xD6, 0x18, 0x18, 0x19, 0x19, 0x40, 0x40, 0x20,
	0x21, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x00,
	0x01, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x2F,
	0x2F, 0x30, 0x30, 0x31, 0x31, 0x40, 0x40, 0x40,
	0x40,
	/* Internal VDD */
	0xD8, 0xA2, 0xAA, 0x02, 0xA0, 0xA2, 0xA8, 0x02,
	0xA0, 0xB0, 0x00, 0x00, 0x00, 0xB0, 0x00, 0x00,
	0x00,
	/* Page 1 bypass */
	0xBD, 0x01,
	0xD8, 0xB0, 0x00, 0x00, 0x00, 0xB0, 0x00, 0x00,
	0x00, 0xE2, 0xAA, 0x03, 0xF0, 0xE2, 0xAA, 0x03,
	0xF0,
	/* Page 2 bypass */
	0xBD, 0x02,
	0xD8, 0xE2, 0xAA, 0x03, 0xF0, 0xE2, 0xAA, 0x03,
	0xF0,
	/* Back to page 0 */
	0xBD, 0x00,
	/* Display control */
	0xB6, 0x8D, 0x8D,
	0xCC, 0x04,
	/* Panel resolution */
	0xC6, 0xFF, 0xF9,
	/* Gamma */
	0xE0, 0x00, 0x12, 0x1F, 0x1A, 0x40, 0x4A, 0x59,
	0x55, 0x5E, 0x67, 0x6F, 0x75, 0x7A, 0x82, 0x8B,
	0x90, 0x95, 0x9F, 0xA3, 0xAD, 0xA2, 0xB2, 0xB6,
	0x5E, 0x5A, 0x65, 0x77, 0x00, 0x12, 0x1F, 0x1A,
	0x40, 0x4A, 0x59, 0x55, 0x5E, 0x67, 0x6F, 0x75,
	0x7A, 0x82, 0x8B, 0x90, 0x95, 0x9F, 0xA3, 0xAD,
	0xA2, 0xB2, 0xB6, 0x5E, 0x5A, 0x65, 0x77,
};

struct canaan_panel {
	struct drm_panel	panel;
	struct mipi_dsi_device	*dsi;
	struct regulator	*power;
	struct gpio_desc	*reset;
	struct gpio_desc	*backlight;
	struct videomode vm;
	u32 width_mm;
	u32 height_mm;
	bool prepared;
};


static inline struct canaan_panel *panel_to_canaan_panel(struct drm_panel *panel)
{
	return container_of(panel, struct canaan_panel, panel);
}

static int canaan_panel_prepare(struct drm_panel *panel)
{
	struct canaan_panel *ctx = panel_to_canaan_panel(panel);
	int ret;

	if (ctx->prepared)
		return 0;

	/* Hardware reset sequence */
	if (ctx->reset) {
		gpiod_set_value(ctx->reset, 1);
		msleep(20);
		gpiod_set_value(ctx->reset, 0);
		msleep(20);
		gpiod_set_value(ctx->reset, 1);
		msleep(50);
	}

	/* Send HX8399 initialization sequence */
	ret = mipi_dsi_dcs_write_buffer(ctx->dsi, hx8399_init_seq,
					 sizeof(hx8399_init_seq));
	if (ret < 0) {
		dev_err(panel->dev, "Failed to send init sequence: %d\n", ret);
		return ret;
	}

	/* Exit sleep mode */
	ret = mipi_dsi_dcs_exit_sleep_mode(ctx->dsi);
	if (ret < 0) {
		dev_err(panel->dev, "Failed to exit sleep mode: %d\n", ret);
		return ret;
	}
	usleep_range(10000, 15000);

	ctx->prepared = true;
	dev_info(panel->dev, "Panel prepared\n");
	return 0;
}

static int canaan_panel_enable(struct drm_panel *panel)
{
	struct canaan_panel *ctx = panel_to_canaan_panel(panel);
	int ret;

	/* Set display on */
	ret = mipi_dsi_dcs_set_display_on(ctx->dsi);
	if (ret < 0) {
		dev_err(panel->dev, "Failed to set display on: %d\n", ret);
		return ret;
	}
	usleep_range(10000, 15000);

	/* Turn on backlight */
	if (ctx->backlight)
		gpiod_set_value(ctx->backlight, 1);

	dev_info(panel->dev, "Panel enabled\n");
	return 0;
}

static int canaan_panel_disable(struct drm_panel *panel)
{
	struct canaan_panel *ctx = panel_to_canaan_panel(panel);

	/* Turn off backlight */
	if (ctx->backlight)
		gpiod_set_value(ctx->backlight, 0);

	return 0;
}

static int canaan_panel_unprepare(struct drm_panel *panel)
{
	struct canaan_panel *ctx = panel_to_canaan_panel(panel);
	int ret;

	if (!ctx->prepared)
		return 0;

	/* Enter sleep mode */
	ret = mipi_dsi_dcs_enter_sleep_mode(ctx->dsi);
	if (ret < 0)
		dev_err(panel->dev, "Failed to enter sleep mode: %d\n", ret);

	/* Hold reset low */
	if (ctx->reset)
		gpiod_set_value(ctx->reset, 0);

	ctx->prepared = false;
	return 0;
}

static int canaan_panel_get_modes(struct drm_panel *panel,
			      struct drm_connector *connector)
{
	struct canaan_panel *ctx = panel_to_canaan_panel(panel);
	struct drm_display_mode *mode;

	mode = drm_mode_create(connector->dev);
	if (!mode) {
		dev_err(panel->dev, "failed to create a new display mode\n");
		return 0;
	}

	drm_display_mode_from_videomode(&ctx->vm, mode);
	mode->width_mm = ctx->width_mm;
	mode->height_mm = ctx->height_mm;
	connector->display_info.width_mm = mode->width_mm;
	connector->display_info.height_mm = mode->height_mm;

	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_probed_add(connector, mode);

	return 1;
}

static const struct drm_panel_funcs canaan_panel_funcs = {
	.prepare	= canaan_panel_prepare,
	.unprepare	= canaan_panel_unprepare,
	.enable		= canaan_panel_enable,
	.disable	= canaan_panel_disable,
	.get_modes	= canaan_panel_get_modes,
};

static int canaan_panel_parse_dt(struct canaan_panel *ctx)
{
	struct device *dev = &ctx->dsi->dev;
	struct device_node *np = dev->of_node;
	int ret;

	ret = of_get_videomode(np, &ctx->vm, 0);
	if (ret < 0)
		return ret;

	of_property_read_u32(np, "panel-width-mm", &ctx->width_mm);
	of_property_read_u32(np, "panel-height-mm", &ctx->height_mm);

	return 0;
}

static int canaan_panel_dsi_probe(struct mipi_dsi_device *dsi)
{
	struct canaan_panel *ctx;
	int ret;

	ctx = devm_kzalloc(&dsi->dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;
	mipi_dsi_set_drvdata(dsi, ctx);
	ctx->dsi = dsi;

	/* Get GPIOs */
	ctx->reset = devm_gpiod_get_optional(&dsi->dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset)) {
		ret = PTR_ERR(ctx->reset);
		dev_err(&dsi->dev, "Failed to get reset GPIO: %d\n", ret);
		return ret;
	}

	ctx->backlight = devm_gpiod_get_optional(&dsi->dev, "backlight", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->backlight)) {
		ret = PTR_ERR(ctx->backlight);
		dev_err(&dsi->dev, "Failed to get backlight GPIO: %d\n", ret);
		return ret;
	}

	ret = canaan_panel_parse_dt(ctx);
	if (ret < 0)
		return ret;

	dsi->mode_flags = MIPI_DSI_MODE_VIDEO_SYNC_PULSE;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->lanes = 4;

	drm_panel_init(&ctx->panel, &dsi->dev, &canaan_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret) {
		drm_panel_remove(&ctx->panel);
		dev_err(&dsi->dev, "Failed to attach DSI: %d\n", ret);
		return ret;
	}

	return 0;
}

static int canaan_panel_dsi_remove(struct mipi_dsi_device *dsi)
{
	struct canaan_panel *ctx = mipi_dsi_get_drvdata(dsi);
	int ret;

	ret = mipi_dsi_detach(dsi);
	if (ret < 0)
		dev_err(&dsi->dev, "Failed to detach DSI: %d\n", ret);

	drm_panel_remove(&ctx->panel);
	return 0;
}

static const struct of_device_id canaan_panel_of_match[] = {
	{ .compatible = "canaan,hx8399" },
	{ }
};
MODULE_DEVICE_TABLE(of, canaan_panel_of_match);

static struct mipi_dsi_driver canaan_panel_dsi_driver = {
	.driver = {
		.name = "panel-canaan-hx8399",
		.of_match_table = canaan_panel_of_match,
	},
	.probe = canaan_panel_dsi_probe,
	.remove = canaan_panel_dsi_remove,
};
module_mipi_dsi_driver(canaan_panel_dsi_driver);

MODULE_AUTHOR("Canaan Bright Sight Co., Ltd");
MODULE_DESCRIPTION("Canaan K230 MIPI DSI Panel Driver (HX8399)");
MODULE_LICENSE("GPL");
