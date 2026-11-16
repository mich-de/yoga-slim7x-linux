// Yoga Slim 7x / WSA884x: attiva (en=1) o disattiva (en=0) il guadagno fisso "PA Volume"
// (bit CSR_GAIN_EN di DRE_CTL_1, che il driver mainline non imposta mai) sugli amplificatori
// il cui prefisso contiene "only" (vuoto = tutti), e imposta il tetto del controllo PA Volume.
// ATTENZIONE: in Linux non c'e' speaker protection. Salire a piccoli passi.
#include <linux/module.h>
#include <linux/platform_device.h>
#include <sound/soc.h>
#define DRE_CTL_1 (0x3000 + 0x0400 + 0xb1)
static int en = 1;
module_param(en, int, 0444);
static int cap = 6;
module_param(cap, int, 0444);
static char *only = "";
module_param(only, charp, 0444);
static const char * const names[] = { "WooferLeft", "WooferRight", "TweeterLeft", "TweeterRight" };
static int __init wsagain_init(void)
{
	struct device *dev;
	struct snd_soc_card *card;
	struct snd_soc_component *c;
	char ctl[48];
	int i;
	if (cap < 0 || cap > 31)
		return -EINVAL;
	dev = bus_find_device_by_name(&platform_bus_type, NULL, "sound");
	if (!dev)
		return -ENODEV;
	card = dev_get_drvdata(dev);
	if (!card || card->dev != dev || !card->instantiated) {
		put_device(dev);
		return -ENODEV;
	}
	for (i = 0; i < ARRAY_SIZE(names); i++) {
		snprintf(ctl, sizeof(ctl), "%s PA Volume", names[i]);
		snd_soc_limit_volume(card, ctl, cap);
	}
	for_each_card_components(card, c) {
		if (!c->name_prefix)
			continue;
		for (i = 0; i < ARRAY_SIZE(names); i++)
			if (!strcmp(c->name_prefix, names[i]))
				break;
		if (i == ARRAY_SIZE(names) || !strstr(c->name_prefix, only))
			continue;
		snd_soc_component_update_bits(c, DRE_CTL_1, 0x01, en ? 0x01 : 0x00);
		pr_info("wsagain: %s CSR_GAIN_EN=%d DRE_CTL_1=0x%02x\n", c->name_prefix, en,
			snd_soc_component_read(c, DRE_CTL_1));
	}
	pr_info("wsagain: PA Volume cap=%d\n", cap);
	put_device(dev);
	return 0;
}
static void __exit wsagain_exit(void) {}
module_init(wsagain_init);
module_exit(wsagain_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("WSA884x fixed PA gain enable");
