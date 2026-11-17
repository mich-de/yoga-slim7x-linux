// SPDX-License-Identifier: GPL-2.0
// Strumento di prova: ritorno V/I degli amplificatori WSA884x verso il DSP, finche' il modulo e' caricato.
//  1) SoundWire: per ognuno dei due bus (WSA, WSA2) uno stream con la porta 5 (VISENSE) dei due
//     amplificatori e le porte del controller date da qcom,port-mapping (10 e 11). Il kernel di serie
//     non lo fa mai: manca il collegamento WSA_AIF_VI nel device tree.
//  2) Macro WSA/WSA2: percorso V/I acceso (stessi registri di wsa_macro_enable_vi_feedback) e
//     TOP_CFG1=0x03 come fa Windows (V e I alternati).
//  3) Sensori V/I degli amplificatori come li imposta Windows (qcaucd8380.sys, carico 4 ohm, 18 dB):
//     ISENSE2 = 6 dB, VSENSE1 = -21 dB. Linux lascia 12 dB e -24 dB e il DSP legge una resistenza sbagliata.
//     Valgono finche' l'altoparlante resta acceso: a ogni riaccensione wsa884x rimette i suoi.
// Non tocca guadagni d'uscita. Tiene svegli bus e amplificatori: rmmod prima di sospendere il portatile.
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include <linux/uaccess.h>
#include <linux/soundwire/sdw.h>
#include <linux/soundwire/sdw_type.h>
#include <sound/soc.h>

#define CDC_WSA_TOP_TOP_CFG1		0x0084
#define SPKR_PROT_RESET			BIT(5)
#define SPKR_PROT_CLK_EN		BIT(4)
#define SPKR_PROT_PCM_RATE_MASK		GENMASK(3, 0)	/* 0 = 8 kHz */
#define VI_PORT				5		/* WSA884X_PORT_VISENSE + 1 */
#define NBUS				2
#define NAMP				2

static const unsigned int tx_path_ctl[] = { 0x0244, 0x0264, 0x0284, 0x02a4 };	/* TX0..TX3 */

static unsigned int chmask = 3;	/* V e I, come Windows nel progetto gemello; il driver di serie dichiara 1 */
module_param(chmask, uint, 0444);
static bool sdw = true;		/* sdw=0: solo le macro, come la prima versione */
module_param(sdw, bool, 0444);
/* campo guadagno (bit 7..5) dei due registri dei sensori; -1 = non toccare */
static int isense;		/* ISENSE2 0x3021: 0 = 6 dB (Windows), 1 = 12 dB (Linux), 2 = 15, 3 = 18 */
module_param(isense, int, 0444);
static int vsense = 3;		/* VSENSE1 0x3020: 3 = -21 dB (Windows), 4 = -24 dB (Linux), 0 = -12 */
module_param(vsense, int, 0444);

/*
 * Offset2 delle porte 10/11 del controller (spaziatura fra i canali, meno uno): 0 come Windows = V e I in
 * due bit vicini. Il device tree ha 0xff: il controller legge i due canali nello stesso bit. -1 = non toccare.
 */
static int off2;
module_param(off2, int, 0444);

static const unsigned int sense_reg[] = { 0x3021, 0x3020 };	/* ISENSE2, VSENSE1 */
#define SENSE_GAIN	GENMASK(7, 5)

/* Copia delle strutture private di drivers/soundwire/qcom.c v7.2.11: serve solo pconfig. */
#define SWRM_MAX_DAIS	0xF
struct qcom_swrm_port_config {
	u16 si;
	u8 off1;
	u8 off2;
	u8 bp_mode;
	u8 hstart;
	u8 hstop;
	u8 word_length;
	u8 blk_group_count;
	u8 lane_control;
};

struct qcom_swrm_ctrl {
	struct sdw_bus bus;
	struct device *dev;
	struct regmap *regmap;
	u32 max_reg;
	const unsigned int *reg_layout;
	void __iomem *mmio;
	struct reset_control *audio_cgcr;
#ifdef CONFIG_DEBUG_FS
	struct dentry *debugfs;
#endif
	struct completion broadcast;
	struct completion enumeration;
	struct mutex port_lock;
	struct clk *hclk;
	int irq;
	unsigned int version;
	int wake_irq;
	int num_din_ports;
	int num_dout_ports;
	int nports;
	int cols_index;
	int rows_index;
	unsigned long port_mask;
	u32 intr_mask;
	u8 rcmd_id;
	u8 wcmd_id;
	struct qcom_swrm_port_config *pconfig;	/* indice = numero di porta, da 1 */
};

static struct vibus {
	struct sdw_stream_runtime *stream;
	struct sdw_slave *amp[NAMP];
	unsigned int sense_old[NAMP][ARRAY_SIZE(sense_reg)];
	int namp, added;
	bool prepared, enabled, sensed, off2_set;
} vb[NBUS];
static int nbus;

/* on: Offset2 di Windows sulle porte V/I del controller; off: di nuovo 0xff */
static int wsavi_off2(struct vibus *v, bool on)
{
	struct sdw_bus *bus = v->amp[0]->bus;
	struct qcom_swrm_ctrl *ctrl = container_of(bus, struct qcom_swrm_ctrl, bus);
	struct qcom_swrm_port_config c[2];
	u8 ora = on ? 0xff : off2;
	int i;

	if (off2 < 0 || off2 > 0xff)
		return 0;
	/* struttura privata: si scrive solo se i valori letti sono quelli del device tree del Yoga */
	if (ctrl->dev != bus->dev->parent || ctrl->nports != 13 || ctrl->num_din_ports != 4 ||
	    copy_from_kernel_nofault(c, &ctrl->pconfig[10], sizeof(c)) ||
	    c[0].si != 0x0f || c[1].si != 0x0f || c[0].off1 != 6 || c[1].off1 != 13 ||
	    c[0].bp_mode != 1 || c[1].bp_mode != 1 || c[0].off2 != ora || c[1].off2 != ora) {
		dev_err(bus->dev, "wsavi: struttura del controller non riconosciuta, Offset2 non toccato\n");
		return -EINVAL;
	}
	for (i = 10; i <= 11; i++)
		ctrl->pconfig[i].off2 = on ? off2 : 0xff;
	v->off2_set = on;
	dev_info(bus->dev, "wsavi: Offset2 delle porte 10 e 11 = %#x\n", on ? off2 : 0xff);
	return 0;
}

/* on: valori di Windows (ricordando quelli trovati); off: rimette quelli trovati */
static void wsavi_sense(struct vibus *v, bool on)
{
	const int want[] = { isense, vsense };
	int i, j;

	for (i = 0; i < v->added; i++) {
		struct regmap *map = dev_get_regmap(&v->amp[i]->dev, NULL);
		unsigned int now[ARRAY_SIZE(sense_reg)] = { 0 };

		for (j = 0; map && j < ARRAY_SIZE(sense_reg); j++) {
			if (want[j] < 0 || want[j] > 7)
				continue;
			if (on)
				regmap_read(map, sense_reg[j], &v->sense_old[i][j]);
			regmap_update_bits(map, sense_reg[j], SENSE_GAIN,
					   on ? want[j] << 5 : v->sense_old[i][j]);
			regmap_read(map, sense_reg[j], &now[j]);
		}
		dev_info(&v->amp[i]->dev, "wsavi: sensori %s: ISENSE2 = %02x, VSENSE1 = %02x\n",
			 on ? "come Windows" : "ripristinati", now[0], now[1]);
	}
	v->sensed = on;
}

static int wsavi_collect(struct device *dev, void *unused)
{
	struct sdw_slave *s;
	int i;

	if (!is_sdw_slave(dev) || !dev->driver || strcmp(dev->driver->name, "wsa884x-codec"))
		return 0;
	s = dev_to_sdw_dev(dev);
	for (i = 0; i < nbus && vb[i].amp[0]->bus != s->bus; i++)
		;
	if (i == NBUS || vb[i].namp == NAMP)
		return -E2BIG;
	if (i == nbus)
		nbus++;
	vb[i].amp[vb[i].namp++] = s;
	get_device(dev);
	return 0;
}

static int wsavi_sdw_on(struct vibus *v)
{
	/*
	 * Direzione RX: per il core e' solo contabilita' (sceglie sink_dpn_prop, dove wsa884x dichiara
	 * la porta 5); il controller Qualcomm non la guarda, le sue porte 10/11 sono ingressi fissi.
	 */
	struct sdw_stream_config sc = {
		.frame_rate = 48000, .ch_count = hweight32(chmask), .bps = 1,
		.direction = SDW_DATA_DIR_RX, .type = SDW_STREAM_PDM,
	};
	struct sdw_port_config sp = { .num = VI_PORT, .ch_mask = chmask }, mp[NAMP];
	int ret;

	v->stream = sdw_alloc_stream("wsavi", SDW_STREAM_PDM);
	if (!v->stream)
		return -ENOMEM;
	for (; v->added < v->namp; v->added++) {
		struct sdw_slave *s = v->amp[v->added];

		mp[v->added] = (struct sdw_port_config){ s->m_port_map[VI_PORT], chmask };
		if (!mp[v->added].num)
			return -EINVAL;
		ret = pm_runtime_resume_and_get(&s->dev);
		if (ret)
			return ret;
		ret = sdw_stream_add_slave(s, &sc, &sp, 1, v->stream);
		if (ret) {
			pm_runtime_put(&s->dev);
			return ret;
		}
	}
	ret = sdw_stream_add_master(v->amp[0]->bus, &sc, mp, v->namp, v->stream);
	if (ret)
		return ret;
	ret = wsavi_off2(v, true);	/* prima di prepare: e' li' che il controller programma le porte */
	if (ret)
		return ret;
	ret = sdw_prepare_stream(v->stream);
	if (ret)
		return ret;
	v->prepared = true;
	ret = sdw_enable_stream(v->stream);
	if (ret)
		return ret;
	v->enabled = true;
	dev_info(v->amp[0]->bus->dev, "wsavi: porta %d di %d amplificatori -> porte %u e %u, maschera %#x\n",
		 VI_PORT, v->namp, mp[0].num, mp[v->namp - 1].num, chmask);
	wsavi_sense(v, true);
	return 0;
}

static void wsavi_sdw_off(struct vibus *v)
{
	int i;

	if (v->sensed)
		wsavi_sense(v, false);
	if (v->enabled)
		sdw_disable_stream(v->stream);
	if (v->prepared)
		sdw_deprepare_stream(v->stream);
	if (v->added)	/* toglie anche gli amplificatori dallo stream */
		sdw_stream_remove_master(v->amp[0]->bus, v->stream);
	if (v->stream)
		sdw_release_stream(v->stream);
	if (v->off2_set)
		wsavi_off2(v, false);
	for (i = 0; i < v->namp; i++) {
		if (i < v->added)
			pm_runtime_put(&v->amp[i]->dev);
		put_device(&v->amp[i]->dev);
	}
}

static int wsavi_macro(bool en)
{
	struct device *dev = bus_find_device_by_name(&platform_bus_type, NULL, "sound");
	struct snd_soc_component *c;
	struct snd_soc_card *card;
	int i;

	if (!dev)
		return -ENODEV;
	card = dev_get_drvdata(dev);
	if (!card || card->dev != dev || !card->instantiated) {
		put_device(dev);
		return -ENODEV;
	}

	for_each_card_components(card, c) {
		if (!c->name_prefix || (strcmp(c->name_prefix, "WSA") && strcmp(c->name_prefix, "WSA2")))
			continue;
		for (i = 0; i < ARRAY_SIZE(tx_path_ctl); i++) {
			snd_soc_component_update_bits(c, tx_path_ctl[i], SPKR_PROT_RESET, SPKR_PROT_RESET);
			snd_soc_component_update_bits(c, tx_path_ctl[i], SPKR_PROT_PCM_RATE_MASK, 0);
			snd_soc_component_update_bits(c, tx_path_ctl[i], SPKR_PROT_CLK_EN,
						      en ? SPKR_PROT_CLK_EN : 0);
			if (en)
				snd_soc_component_update_bits(c, tx_path_ctl[i], SPKR_PROT_RESET, 0);
		}
		if (en)
			snd_soc_component_write(c, CDC_WSA_TOP_TOP_CFG1, 0x03);
		pr_info("wsavi: %s en=%d TX0..3 = %02x %02x %02x %02x TOP_CFG1 = %02x\n", c->name_prefix, en,
			snd_soc_component_read(c, tx_path_ctl[0]), snd_soc_component_read(c, tx_path_ctl[1]),
			snd_soc_component_read(c, tx_path_ctl[2]), snd_soc_component_read(c, tx_path_ctl[3]),
			snd_soc_component_read(c, CDC_WSA_TOP_TOP_CFG1));
	}
	put_device(dev);
	return 0;
}

static void wsavi_off(void)
{
	int i;

	wsavi_macro(false);
	for (i = 0; i < nbus; i++)
		wsavi_sdw_off(&vb[i]);
}

static int __init wsavi_init(void)
{
	int i, ret = 0;

	if (sdw)
		ret = bus_for_each_dev(&sdw_bus_type, NULL, NULL, wsavi_collect);
	for (i = 0; !ret && i < nbus; i++)
		ret = wsavi_sdw_on(&vb[i]);
	if (!ret)	/* dopo SoundWire: i clock delle macro partono con i dati gia' in arrivo */
		ret = wsavi_macro(true);
	if (ret) {
		pr_err("wsavi: errore %d, tutto spento\n", ret);
		wsavi_off();
	}
	return ret;
}

static void __exit wsavi_exit(void)
{
	wsavi_off();
}

module_init(wsavi_init);
module_exit(wsavi_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("WSA884x V/I feedback over SoundWire + WSA macro path (test tool)");
