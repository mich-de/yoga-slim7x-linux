// Yoga Slim 7x / WSA884x: scrive un campo di registro sugli amplificatori il cui prefisso contiene "only".
// Strumento di prova: nessuna protezione altoparlanti in Linux, usare solo per abbassare o a piccoli passi.
#include <linux/module.h>
#include <linux/platform_device.h>
#include <sound/soc.h>
static unsigned int reg, mask = 0xff, val;
module_param(reg, uint, 0444); module_param(mask, uint, 0444); module_param(val, uint, 0444);
static char *only = "";
module_param(only, charp, 0444);
static int __init wsareg_init(void)
{
	struct device *dev = bus_find_device_by_name(&platform_bus_type, NULL, "sound");
	struct snd_soc_card *card;
	struct snd_soc_component *c;
	if (!dev)
		return -ENODEV;
	card = dev_get_drvdata(dev);
	if (!card || card->dev != dev || !card->instantiated || reg < 0x3000 || reg > 0x38ff) {
		put_device(dev);
		return -EINVAL;
	}
	for_each_card_components(card, c) {
		unsigned int old;
		if (!c->name_prefix || (!strstr(c->name_prefix, "eft") && !strstr(c->name_prefix, "ight")))
			continue;
		if (!strstr(c->name_prefix, only))
			continue;
		old = snd_soc_component_read(c, reg);
		snd_soc_component_update_bits(c, reg, mask, val);
		pr_info("wsareg: %s reg 0x%04x: 0x%02x -> 0x%02x\n", c->name_prefix, reg, old, snd_soc_component_read(c, reg));
	}
	put_device(dev);
	return 0;
}
static void __exit wsareg_exit(void) {}
module_init(wsareg_init);
module_exit(wsareg_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("WSA884x register field write (test tool)");
