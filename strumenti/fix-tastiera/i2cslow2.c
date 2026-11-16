// Corregge in memoria la clock-frequency del bus I2C di tastiera/touchpad (Yoga Slim 7x).
// Dopo il caricamento va fatto unbind/bind di geni_i2c su b80000.i2c.
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
static char *path = "/soc@0/geniqup@bc0000/i2c@b80000";
module_param(path, charp, 0444);
static unsigned int freq = 100000;
module_param(freq, uint, 0444);
static int __init i2cslow_init(void)
{
	struct device_node *np = of_find_node_by_path(path);
	struct property *p;
	__be32 *nv;
	if (!np)
		return -ENODEV;
	p = of_find_property(np, "clock-frequency", NULL);
	if (!p || p->length != 4) {
		of_node_put(np);
		return -EINVAL;
	}
	pr_info("i2cslow: %s clock-frequency %u -> %u\n", path,
		be32_to_cpup(p->value), freq);
	nv = kmalloc(sizeof(*nv), GFP_KERNEL);
	if (!nv) { of_node_put(np); return -ENOMEM; }
	*nv = cpu_to_be32(freq);
	p->value = nv;
	of_node_put(np);
	return 0;
}
static void __exit i2cslow_exit(void) {}
module_init(i2cslow_init);
module_exit(i2cslow_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Yoga Slim 7x: I2C keyboard bus at 100 kHz");
