#!/usr/bin/env python3
"""Audio Yoga: profili audio del Yoga Slim 7x su Fedora. Comanda il filtro PipeWire "Audio Yoga", che fa lavorare
il codice Dolby dell'altoparlante preso dal Windows del portatile.
  audio_yoga.py               apre la finestra
  audio_yoga.py --vassoio     parte nel vassoio di sistema
  audio_yoga.py --ripristina  applica l'ultimo stato salvato ed esce (avvio automatico all'accesso)
"""
import json
import os
import subprocess
import sys

NODO = os.environ.get("AUDIO_YOGA_NODO", "effect_input.audio_yoga")
PROFILI = ["Dinamico", "Film", "Musica", "Gioco", "Voce", "Spento"]
FREQ = [47, 141, 234, 328, 469, 656, 844, 1031, 1313, 1688, 2250, 3000, 3750, 4688, 5813, 7125, 9000, 11250, 13875, 19688]
STATO = os.path.expanduser("~/.config/audio-yoga/stato.json")
CARTELLE = [os.environ.get("AUDIO_YOGA_DIR", ""), "/run/strumenti/dolby-privato", "/opt/yoga-slim7x/dolby-privato"]
CHIAVI = ["dynamic", "movie", "music", "game", "voice", "off"]  # nomi dei profili nella taratura
# surround, dialoghi, livellatore: None = come dice il profilo
PREDEFINITO = {"profilo": 2, "spinta": False, "eq": False, "preset": "Personale", "bande": [0.0] * 20,
               "surround": None, "dialoghi": None, "livellatore": None}


def nodo_id():
    """Identificativo del nodo PipeWire del filtro, o None se il servizio non gira."""
    try:
        out = subprocess.run(["pw-cli", "ls", "Node"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    ident = None
    for riga in out.splitlines():
        r = riga.strip()
        if r.startswith("id "):
            ident = r.split()[1].rstrip(",")
        elif r == f'node.name = "{NODO}"':
            return ident
    return None


def applica(stato):
    """Manda lo stato al filtro. Ritorna False se il filtro non c'e'."""
    ident = nodo_id()
    if ident is None:
        return False
    bande = stato["bande"] if stato["eq"] else [0.0] * 20
    p = [f'"dolby:Profilo" {int(stato["profilo"])}', f'"dolby:Spinta" {6.0 if stato["spinta"] else 0.0}']
    for nome, chiave in (("Surround", "surround"), ("Dialoghi", "dialoghi"), ("Livellatore", "livellatore")):
        v = stato.get(chiave)
        p.append(f'"dolby:{nome}" {-1 if v is None else int(v)}')
    p += [f'"dolby:EQ {i + 1}" {float(b):.2f}' for i, b in enumerate(bande)]
    try:
        r = subprocess.run(["pw-cli", "set-param", ident, "Props", "{ params = [ " + " ".join(p) + " ] }"],
                           capture_output=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return r.returncode == 0


def leggi_stato():
    s = dict(PREDEFINITO)
    try:
        letto = json.load(open(STATO))
        s.update({k: letto[k] for k in PREDEFINITO if k in letto})
    except (OSError, ValueError):
        pass
    try:  # un file rovinato non deve bloccare l'app
        s["profilo"] = min(max(int(s["profilo"]), 0), len(PROFILI) - 1)
        s["bande"] = [min(max(float(b), -12.0), 12.0) for b in s["bande"]][:20]
        assert len(s["bande"]) == 20
        for k, massimo in (("surround", 1), ("dialoghi", 16), ("livellatore", 10)):
            s[k] = None if s[k] is None else min(max(int(s[k]), 0), massimo)
    except (TypeError, ValueError, AssertionError):
        s = dict(PREDEFINITO)
    return s


def salva_stato(s):
    os.makedirs(os.path.dirname(STATO), exist_ok=True)
    with open(STATO + ".tmp", "w") as f:
        json.dump(s, f)
    os.replace(STATO + ".tmp", STATO)


def preset():
    """Curve pronte: differenza fra i bersagli dell'equalizzatore della taratura e quello bilanciato, in dB."""
    p = {"Personale": None, "Piatto": [0.0] * 20}
    for c in CARTELLE:
        try:
            righe = [r.split() for r in open(os.path.join(c, "profili.txt")) if r.startswith("costanti ieq_")]
        except OSError:
            continue
        t = {r[1]: [int(v) for v in r[3:23]] for r in righe}
        if "ieq_balanced" in t:
            for chiave, nome in (("ieq_detailed", "Dettagliato"), ("ieq_warm", "Caldo")):
                if chiave in t:
                    d = [(a - b) / 16.0 for a, b in zip(t[chiave], t["ieq_balanced"])]
                    m = sum(d) / len(d)
                    p[nome] = [round(min(max(x - m, -12.0), 12.0), 1) for x in d]
        break
    return p


def del_profilo():
    """Che cosa prevede la taratura per ogni profilo: surround, dialoghi (0 = spenti), livellatore (0 = spento)."""
    d = [{"surround": 0, "dialoghi": 0, "livellatore": 0} for _ in PROFILI]
    for c in CARTELLE:
        try:
            righe = [r.split() for r in open(os.path.join(c, "profili.txt")) if " cp." in r]
        except OSError:
            continue
        v = {(r[0], r[1]): int(r[3]) for r in righe if len(r) > 3}
        for i, k in enumerate(CHIAVI):
            d[i]["surround"] = v.get((k, "cp.surround-decoder-enable"), 0)
            d[i]["dialoghi"] = v.get((k, "cp.dialog-enhancer-amount"), 0) if v.get((k, "cp.dialog-enhancer-enable")) else 0
            d[i]["livellatore"] = v.get((k, "cp.volume-leveler-amount"), 0) if v.get((k, "cp.volume-leveler-enable")) else 0
        break
    return d


def main():
    if "--ripristina" in sys.argv:
        return 0 if applica(leggi_stato()) else 1
    from PySide6 import QtCore, QtGui, QtWidgets

    app = QtWidgets.QApplication(sys.argv)
    app.setApplicationName("Audio Yoga")
    app.setQuitOnLastWindowClosed(False)

    def icona():
        px = QtGui.QPixmap(64, 64)
        px.fill(QtCore.Qt.transparent)
        g = QtGui.QPainter(px)
        g.setRenderHint(QtGui.QPainter.Antialiasing)
        g.setBrush(QtGui.QColor("#1f6f78"))
        g.setPen(QtCore.Qt.NoPen)
        g.drawRoundedRect(2, 2, 60, 60, 12, 12)
        g.setBrush(QtGui.QColor("#ffffff"))
        for x, h in ((14, 22), (27, 38), (40, 28)):
            g.drawRoundedRect(x, 50 - h, 9, h, 3, 3)
        g.end()
        return QtGui.QIcon(px)

    class Finestra(QtWidgets.QWidget):
        def __init__(self):
            super().__init__()
            self.stato = leggi_stato()
            self.preset = preset()
            self.setWindowTitle("Audio Yoga")
            self.setWindowIcon(icona())
            v = QtWidgets.QVBoxLayout(self)
            v.addWidget(QtWidgets.QLabel("<b>Profilo</b>"))
            griglia = QtWidgets.QGridLayout()
            self.gruppo = QtWidgets.QButtonGroup(self)
            for i, nome in enumerate(PROFILI):
                b = QtWidgets.QPushButton(nome)
                b.setCheckable(True)
                b.setMinimumHeight(36)
                self.gruppo.addButton(b, i)
                griglia.addWidget(b, i // 3, i % 3)
            v.addLayout(griglia)
            self.spinta = QtWidgets.QCheckBox("Volume massimo (+6 dB, trattenuto dal regolatore)")
            v.addWidget(self.spinta)
            riga = QtWidgets.QHBoxLayout()
            self.eq = QtWidgets.QCheckBox("Equalizzatore")
            self.scelta = QtWidgets.QComboBox()
            self.scelta.addItems(list(self.preset))
            riga.addWidget(self.eq)
            riga.addWidget(self.scelta, 1)
            v.addLayout(riga)
            bande = QtWidgets.QHBoxLayout()
            bande.setSpacing(2)
            self.cursori = []
            for f in FREQ:
                col = QtWidgets.QVBoxLayout()
                c = QtWidgets.QSlider(QtCore.Qt.Vertical)
                c.setRange(-120, 120)
                c.setPageStep(10)
                c.setMinimumHeight(120)
                c.setAccessibleName(f"Banda {f} hertz")
                e = QtWidgets.QLabel(f"{f / 1000:.0f}k" if f >= 10000 else f"{f / 1000:.1f}k" if f >= 1000 else str(f))
                e.setAlignment(QtCore.Qt.AlignHCenter)
                e.setStyleSheet("font-size: 8pt")
                col.addWidget(c, 0, QtCore.Qt.AlignHCenter)
                col.addWidget(e)
                bande.addLayout(col)
                self.cursori.append(c)
            v.addLayout(bande)
            self.profili = del_profilo()
            effetti = QtWidgets.QGridLayout()
            self.surround = QtWidgets.QCheckBox("Surround virtuale")
            self.dialoghi = QtWidgets.QCheckBox("Dialoghi più chiari")
            self.livellatore = QtWidgets.QCheckBox("Volume uniforme")
            self.q_dialoghi = QtWidgets.QSlider(QtCore.Qt.Horizontal)
            self.q_dialoghi.setRange(1, 16)
            self.q_dialoghi.setAccessibleName("Quantità dei dialoghi")
            self.q_livellatore = QtWidgets.QSlider(QtCore.Qt.Horizontal)
            self.q_livellatore.setRange(1, 10)
            self.q_livellatore.setAccessibleName("Quantità del volume uniforme")
            effetti.addWidget(self.surround, 0, 0)
            effetti.addWidget(self.dialoghi, 1, 0)
            effetti.addWidget(self.q_dialoghi, 1, 1)
            effetti.addWidget(self.livellatore, 2, 0)
            effetti.addWidget(self.q_livellatore, 2, 1)
            v.addLayout(effetti)
            self.riga_stato = QtWidgets.QLabel()
            self.riga_stato.setWordWrap(True)
            v.addWidget(self.riga_stato)
            self.attesa = QtCore.QTimer(self, singleShot=True, interval=150, timeout=self.manda)
            self.mostra()
            self.gruppo.idClicked.connect(self.cambia_profilo)
            for w in (self.surround, self.dialoghi, self.livellatore):
                w.clicked.connect(self.cambia_effetti)
            for w in (self.q_dialoghi, self.q_livellatore):
                w.valueChanged.connect(self.cambia_effetti)
            self.spinta.toggled.connect(self.cambia)
            self.eq.toggled.connect(self.cambia)
            self.scelta.activated.connect(self.cambia_preset)
            for c in self.cursori:
                c.valueChanged.connect(self.cambia_banda)
            self.manda()

        def mostra(self):
            """Porta lo stato sui comandi senza far partire i segnali."""
            comandi = [self.spinta, self.eq, self.scelta, self.surround, self.dialoghi, self.livellatore,
                       self.q_dialoghi, self.q_livellatore] + self.cursori
            for w in comandi:
                w.blockSignals(True)
            self.gruppo.button(self.stato["profilo"]).setChecked(True)
            self.spinta.setChecked(bool(self.stato["spinta"]))
            self.eq.setChecked(bool(self.stato["eq"]))
            i = self.scelta.findText(self.stato["preset"])
            self.scelta.setCurrentIndex(i if i >= 0 else 0)
            for c, b in zip(self.cursori, self.stato["bande"]):
                c.setValue(round(b * 10))
                c.setEnabled(bool(self.stato["eq"]))
            self.scelta.setEnabled(bool(self.stato["eq"]))
            base = self.profili[self.stato["profilo"]]  # dove l'utente non ha scelto vale il profilo
            vale = {k: base[k] if self.stato[k] is None else self.stato[k] for k in base}
            self.surround.setChecked(bool(vale["surround"]))
            self.dialoghi.setChecked(vale["dialoghi"] > 0)
            self.livellatore.setChecked(vale["livellatore"] > 0)
            self.q_dialoghi.setValue(vale["dialoghi"] or 5)
            self.q_livellatore.setValue(vale["livellatore"] or 5)
            self.q_dialoghi.setEnabled(vale["dialoghi"] > 0)
            self.q_livellatore.setEnabled(vale["livellatore"] > 0)
            for w in comandi:
                w.blockSignals(False)

        def cambia_profilo(self, i):
            self.stato["profilo"] = i
            self.stato.update(surround=None, dialoghi=None, livellatore=None)  # ogni profilo riparte dai suoi valori
            self.mostra()
            self.manda()

        def cambia_effetti(self):
            self.stato["surround"] = int(self.surround.isChecked())
            self.stato["dialoghi"] = self.q_dialoghi.value() if self.dialoghi.isChecked() else 0
            self.stato["livellatore"] = self.q_livellatore.value() if self.livellatore.isChecked() else 0
            self.mostra()
            self.attesa.start()

        def cambia(self):
            self.stato["spinta"] = self.spinta.isChecked()
            self.stato["eq"] = self.eq.isChecked()
            self.mostra()
            self.manda()

        def cambia_preset(self):
            nome = self.scelta.currentText()
            self.stato["preset"] = nome
            if self.preset.get(nome):
                self.stato["bande"] = list(self.preset[nome])
            self.mostra()
            self.manda()

        def cambia_banda(self):
            self.stato["bande"] = [c.value() / 10 for c in self.cursori]
            self.stato["preset"] = "Personale"
            self.scelta.setCurrentIndex(0)
            self.attesa.start()

        def manda(self):
            ok = applica(self.stato)
            salva_stato(self.stato)
            self.riga_stato.setText("Uscita: Audio Yoga → Altoparlanti potenziati" if ok else
                                    "Il filtro Audio Yoga non è attivo: l'audio passa senza elaborazione.")
            if hasattr(self, "al_cambio"):
                self.al_cambio()
            # all'accesso il filtro puo' partire dopo l'app: si riprova per mezzo minuto
            self.tentativi = 0 if ok else getattr(self, "tentativi", 0) + 1
            if not ok and self.tentativi <= 15:
                QtCore.QTimer.singleShot(2000, self.manda)

        def closeEvent(self, ev):
            if QtWidgets.QSystemTrayIcon.isSystemTrayAvailable():
                self.hide()
                ev.ignore()
            else:
                QtWidgets.QApplication.quit()

    f = Finestra()
    if QtWidgets.QSystemTrayIcon.isSystemTrayAvailable():
        vassoio = QtWidgets.QSystemTrayIcon(icona(), app)
        menu = QtWidgets.QMenu()
        azioni = QtGui.QActionGroup(menu)
        for i, nome in enumerate(PROFILI):
            a = menu.addAction(nome)
            a.setCheckable(True)
            a.setData(i)
            azioni.addAction(a)
        menu.addSeparator()
        menu.addAction("Apri Audio Yoga", lambda: (f.show(), f.raise_(), f.activateWindow()))
        menu.addAction("Esci", app.quit)

        def scelto(a):
            f.cambia_profilo(a.data())

        def aggiorna():
            azioni.actions()[f.stato["profilo"]].setChecked(True)
            vassoio.setToolTip("Audio Yoga: " + PROFILI[f.stato["profilo"]])

        azioni.triggered.connect(scelto)
        f.al_cambio = aggiorna
        aggiorna()
        vassoio.setContextMenu(menu)
        vassoio.activated.connect(lambda motivo: (f.show(), f.raise_()) if motivo == QtWidgets.QSystemTrayIcon.Trigger else None)
        vassoio.show()
    if "--vassoio" not in sys.argv or not QtWidgets.QSystemTrayIcon.isSystemTrayAvailable():
        f.show()
    if "--prova" in sys.argv:  # usata da prove/prova_app.sh: preme un profilo, accende la spinta, esce
        f.gruppo.button(0).click()
        f.spinta.setChecked(True)
        f.livellatore.click()
        QtCore.QTimer.singleShot(400, app.quit)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
