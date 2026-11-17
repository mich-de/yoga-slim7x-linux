// SPDX-License-Identifier: GPL-2.0
// Rimette nel router GPR la porta di un servizio del DSP dopo lo sgancio del suo driver.
// apr.c registra la porta solo quando crea il dispositivo e la toglie a ogni sgancio: un driver
// agganciato dopo non riceve piu' risposte ("GPR: Port(1) is not registered"). Serve solo allo
// scambio a caldo (scambia.sh): con i moduli caricati all'avvio non c'e' nessuno sgancio.
#include <linux/idr.h>
#include <linux/module.h>
#include <linux/soc/qcom/apr.h>

/* shortcut: inizio di struct packet_router, privata di apr.c (v7.2.11); a ogni kernel nuovo va riconfrontata */
struct packet_router_head {
	struct rpmsg_endpoint *ch;
	struct device *dev;
	spinlock_t svcs_lock;
	spinlock_t rx_lock;
	struct idr svcs_idr;
};

static char *dev = "gprsvc:service:2:1";
module_param(dev, charp, 0444);

static int __init gprport_init(void)
{
	struct device *d = bus_find_device_by_name(&aprbus, NULL, dev);
	struct packet_router_head *pr;
	struct apr_device *adev;
	unsigned long flags;
	int ret = 0;

	if (!d)
		return -ENODEV;

	adev = to_apr_device(d);
	pr = dev_get_drvdata(d->parent);
	/* the copied layout is only trusted if it points back at the router device */
	if (!pr || pr->dev != d->parent || (void *)adev->svc.pr != (void *)pr) {
		put_device(d);
		return -EINVAL;
	}

	spin_lock_irqsave(&pr->svcs_lock, flags);
	/*
	 * Without a bound driver the callback still points at the driver that left, possibly
	 * an unloaded module: a reply arriving during the next probe would jump into freed
	 * code (seen: Oops in the GPR receive worker, audio dead until reboot). apr.c sets
	 * the callback again when the new probe succeeds and skips a NULL one.
	 */
	if (!d->driver)
		adev->svc.callback = NULL;
	if (!idr_find(&pr->svcs_idr, adev->svc.id))
		ret = idr_alloc(&pr->svcs_idr, &adev->svc, adev->svc.id,
				adev->svc.id + 1, GFP_ATOMIC);
	else
		ret = -EEXIST;
	spin_unlock_irqrestore(&pr->svcs_lock, flags);

	pr_info("gprport: %s port %d: %d\n", dev, adev->svc.id, ret);
	put_device(d);

	return ret < 0 && ret != -EEXIST ? ret : 0;
}

static void __exit gprport_exit(void) {}

module_init(gprport_init);
module_exit(gprport_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Re-register a GPR service port after a driver unbind");
