# SPDX-License-Identifier: BSD-3-Clause
# Sottografo del dispositivo con protezione altoparlanti del DSP (come il grafo di Windows):
#   contenitore 1: [LOG] -> [MFC] -> [SP_RX] -> [CODEC DMA SINK]
#   contenitore 2: [CODEC DMA SOURCE, ritorno V/I] -> [SP_VI]
# Gli identificativi di SP_RX, SP_VI e della sorgente V/I sono quelli di Windows:
# il file di taratura (yoga-slim7x-spkr-prot.bin) li indirizza cosi'.
include(`audioreach/audioreach.m4') dnl
include(`util/pcm.m4') dnl
include(`audioreach/subgraph.m4') dnl
include(`audioreach/container.m4') dnl
include(`audioreach/module_mfc.m4') dnl
include(`audioreach/module_log.m4') dnl
include(`audioreach/module_codec_dma.m4') dnl
include(`util/mixer.m4') dnl
dnl
undefine(`CDC_DMA_MODULE_IID') dnl
undefine(`LOG_MODULE_IID') dnl
undefine(`MFC_MODULE_IID') dnl
undefine(`SG_INDEX') dnl
undefine(`CONTAINER_INDEX') dnl
undefine(`MOD_INDEX') dnl
undefine(`DEVICE_PERF_MODE') dnl
undefine(`DEVICE_DIRECTION') dnl
undefine(`CONT_SENARIO_ID') dnl
undefine(`CONT_CAP') dnl
undefine(`CONT_POSITION') dnl
undefine(`DEVICE_DOMAIN_ID') dnl
undefine(`CONT_STACK_SIZE') dnl
dnl
define(`PCM_PERF_MODE', APM_SG_PERF_MODE_LOW_LATENCY) dnl'
define(`PCM_DIRECTION', APM_SUB_GRAPH_DIRECTION_RX) dnl'
define(`DEVICE_PERF_MODE', APM_SG_PERF_MODE_LOW_LATENCY) dnl'
define(`DEVICE_DIRECTION', APM_SUB_GRAPH_DIRECTION_TX) dnl'
define(`CONT_SENARIO_ID', APM_SUB_GRAPH_SID_AUDIO_PLAYBACK) dnl'
define(`CONT_CAP', `ifelse(LPASS_VER_COMPAT, 110000, APM_CONTAINER_TYPE_ID_GC, APM_CONTAINER_CAP_ID_EP)') dnl'
define(`CONT_POSITION', APM_CONT_GRAPH_POS_STREAM)dnl'
define(`DEVICE_DOMAIN_ID', ifdef(`AR_SELECTED_PROC_DOMAIN_ID', `AR_SELECTED_PROC_DOMAIN_ID', `APM_PROC_DOMAIN_ID_ADSP')) dnl'
define(`CONT_STACK_SIZE', 8192) dnl'
dnl
define(`LOG_MODULE_IID', MOD_IID_START) dnl
define(`MFC_MODULE_IID', eval(MOD_IID_START + 1)) dnl
define(`CDC_DMA_MODULE_IID', eval(MOD_IID_START + 2)) dnl
define(`SP_RX_MODULE_IID', 0x0000411A) dnl
define(`SP_VI_MODULE_IID', 0x00004121) dnl
define(`VI_DMA_MODULE_IID', 0x0000411B) dnl
define(`MODULE_ID_SP_RX', 0x070010E2) dnl
define(`MODULE_ID_SP_VI', 0x070010E3) dnl
define(`SG_INDEX', 1) dnl
define(`CONTAINER_INDEX', 1) dnl
define(`VI_CONTAINER_INDEX', 2) dnl
define(`MOD_INDEX', 1) dnl
dnl
dnl AR_MODULE_SP(nome, index, sgidx, container-idx, iid, module-id, maxip-ports, max-op-ports, dst-iid)
define(`AR_MODULE_SP',
`'
`SectionVendorTuples."NAME_PREFIX.$1$2_tuples" {'
`        tokens "audioreach_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($5)'
`                AR_TKN_U32_MODULE_ID STR($6)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR($7)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR($8)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR(1)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR(2)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($5)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($9)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.$1$2_data" {'
`        tuples "NAME_PREFIX.$1$2_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.$1$2" {'
`        index STR($2)'
`        type "buffer"'
`        no_pm "true"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$3_data"'
`                "NAME_PREFIX.container$4_data"'
`                "NAME_PREFIX.$1$2_data"'
`        ]'
`}') dnl
dnl
dnl AR_MODULE_VI_DMA(index, sgidx, container-idx, iid, hw-if-type, hw-if-idx, fmt, dst-iid)
dnl Sorgente codec DMA senza stream ALSA: parte e si ferma con il grafo di riproduzione.
define(`AR_MODULE_VI_DMA',
`'
`SectionVendorTuples."NAME_PREFIX.vi_dma$1_tuples" {'
`        tokens "audioreach_tokens"'
`'
`        tuples."word.u32_data" {'
`                AR_TKN_U32_MODULE_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_ID STR(MODULE_ID_CODEC_DMA_SOURCE)'
`                AR_TKN_U32_MODULE_MAX_IP_PORTS STR(0)'
`                AR_TKN_U32_MODULE_MAX_OP_PORTS STR(1)'
`                AR_TKN_U32_MODULE_SRC_OP_PORT_ID STR(1)'
`                AR_TKN_U32_MODULE_DST_IN_PORT_ID STR(2)'
`                AR_TKN_U32_MODULE_SRC_INSTANCE_ID STR($4)'
`                AR_TKN_U32_MODULE_DST_INSTANCE_ID STR($8)'
`                AR_TKN_U32_MODULE_HW_IF_TYPE STR($5)'
`                AR_TKN_U32_MODULE_HW_IF_IDX STR($6)'
`                AR_TKN_U32_MODULE_FMT_DATA STR($7)'
`        }'
`}'
`'
`SectionData."NAME_PREFIX.vi_dma$1_data" {'
`        tuples "NAME_PREFIX.vi_dma$1_tuples"'
`}'
`'
`SectionWidget."NAME_PREFIX.vi_dma$1" {'
`        index STR($1)'
`        type "buffer"'
`        no_pm "true"'
`        subseq "10"'
`        data ['
`                "NAME_PREFIX.sub_graph$2_data"'
`                "NAME_PREFIX.container$3_data"'
`                "NAME_PREFIX.vi_dma$1_data"'
`        ]'
`}') dnl
dnl
dnl DEVICE_PLAYBACK_ROUTE(stream-index, dai-id): percorso DAPM invariato, i moduli di protezione
dnl sono collegati solo nel grafo del DSP.
define(`DEVICE_PLAYBACK_ROUTE',
`'
`SectionGraph."NAME_PREFIX.$1 $2 Graph" {'
`        index STR($1)'
`        lines ['
`                "NAME_PREFIX.logger$1, , $2 Audio Mixer"'
`                "NAME_PREFIX.mfc$1, , NAME_PREFIX.logger$1"'
`                "NAME_PREFIX.codec_dma_rx$1, , NAME_PREFIX.mfc$1"'
`                "$2 Playback, , NAME_PREFIX.codec_dma_rx$1"'
`        ]'
`}')

AR_SUBGRAPH(SG_INDEX, DEVICE_DAI_ID, SG_IID_START, DEVICE_PERF_MODE, DEVICE_DIRECTION, CONT_SENARIO_ID)
AR_CONTAINER(CONTAINER_INDEX, CONT_IID_START, CONT_CAP, CONT_STACK_SIZE, CONT_POSITION, DEVICE_DOMAIN_ID)
AR_MODULE_LOG(MOD_INDEX, SG_INDEX, CONTAINER_INDEX, 		LOG_MODULE_IID,     1, 1, 1, 2, 0x000019ab, 1, 0, MFC_MODULE_IID)
AR_MODULE_MFC(MOD_INDEX, SG_INDEX, CONTAINER_INDEX,	MFC_MODULE_IID, 1, 1, 1, 2, SP_RX_MODULE_IID)
AR_MODULE_SP(sp_rx, MOD_INDEX, SG_INDEX, CONTAINER_INDEX, SP_RX_MODULE_IID, MODULE_ID_SP_RX, 1, 1, CDC_DMA_MODULE_IID)
AR_MODULE_CODEC_DMA_RX(MOD_INDEX, SG_INDEX, CONTAINER_INDEX, CDC_DMA_MODULE_IID, 1, 0, 1, 0, DEVICE_INTF_TYPE, DEVICE_INTF_INDEX, DEVICE_DATA_FORMAT, `DEVICE_NAME', NONE_IID)
dnl Contenitore del ritorno V/I: stack 4096 come in Windows, posizione "dispositivo globale".
AR_CONTAINER(VI_CONTAINER_INDEX, eval(CONT_IID_START + 1), CONT_CAP, 4096, APM_CONT_GRAPH_POS_GLOBAL_DEV, DEVICE_DOMAIN_ID)
AR_MODULE_VI_DMA(MOD_INDEX, SG_INDEX, VI_CONTAINER_INDEX, VI_DMA_MODULE_IID, DEVICE_INTF_TYPE, CODEC_INTF_IDX_TX0, DEVICE_DATA_FORMAT, SP_VI_MODULE_IID)
AR_MODULE_SP(sp_vi, MOD_INDEX, SG_INDEX, VI_CONTAINER_INDEX, SP_VI_MODULE_IID, MODULE_ID_SP_VI, 1, 0, NONE_IID)
DEVICE_PLAYBACK_ROUTE(MOD_INDEX, `DEVICE_NAME')
