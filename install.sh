#!/usr/bin/env bash
# kasper.sh/linux - post-install setup for Linux Mint, Debian, Fedora and Arch
#   Nordic/European localisation + a desktop that looks like the one you know.
# Usage:  curl -fsSL https://kasper.sh/linux/install.sh | bash
#         bash install.sh --distro fedora --style win10 --panel

# This script is bash, not POSIX sh. Piping into `sh` skips the shebang and
# lands us in dash, which dies on `pipefail` with a useless message - so say so
# first, in syntax dash can actually parse.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "kasper.sh/linux skal koeres med bash, ikke sh." >&2
  echo "" >&2
  echo "  curl -fsSL https://kasper.sh/linux/install.sh | bash" >&2
  echo "" >&2
  exit 1
fi

set -euo pipefail

# Not VERSION: /etc/os-release is sourced further down and would overwrite it.
SCRIPT_VERSION="4.2.0"
DISTRO=""              # debian|ubuntu|mint|fedora|arch (empty = detect, then ask)
DESKTOP=""             # cinnamon | gnome | xfce | mate | plasma | other
                       #                               (empty = detect, then ask)
LANG_CHOICE=""         # da | nb | sv | fi | de | en   (empty = ask)
UI_LANG=""             # language for the script's own output (default: LANG_CHOICE)
KEYBOARD=""            # override the layout that comes with the language
KB_VARIANT=""          # nodeadkeys, intl, ... (empty = the plain layout)
TIMEZONE=""            # override the timezone that comes with the language
STYLE=""               # win11 | win10 | mac | arc | mint | none  (empty = ask)
MENU=""                # system | zorin | cinnamenu    (empty = ask)
VARIANT=""             # light | dark                  (empty = ask)
LAYOUT=""              # traditional | mint            (empty = ask)
PKG=""                 # apt | dnf | pacman            (follows DISTRO)
DESKLABEL=""           # what to call the desktop in a message
DISTROLABEL=""         # what to call the system in a message
# The button icon for any menu this script installs: the generic system icon
# the desktop already uses, never a vendor's or an extension's own logo. It
# resolves through whichever icon theme is active, so it always matches.
MENU_ICON="start-here-symbolic"
DO_LANG=1
DO_THEME=1
DRY_RUN=0
ASSUME_YES=0
WORKDIR="${TMPDIR:-/tmp}/linux-themes.$$"

# ---------- output helpers ----------------------------------------------------
if [ -t 1 ]; then C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
step() { printf '\n%s==>%s %s%s%s\n' "$C_B" "$C_0" "$C_B" "$*" "$C_0"; }
ok()   { printf '  %s[ok]%s %s\n' "$C_G" "$C_0" "$*"; }
note() { printf '  %s[..]%s %s\n' "$C_Y" "$C_0" "$*"; }
warn() { printf '  %s[!!]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { warn "$*"; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$*"; else "$@"; fi; }
# same, but silence stdout on a real run (the [dry] line must still show)
runq() { if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$*"; else "$@" >/dev/null; fi; }

usage() {
  cat <<EOF
kasper.sh/linux $SCRIPT_VERSION

  --distro debian|ubuntu|mint|fedora|arch
                                  Which system this is. It picks the package
                                  manager - apt for Debian, Ubuntu and Mint,
                                  dnf for Fedora, pacman for Arch - and the
                                  package names, which differ on all three.
                                  Omit it and the script detects it, and asks
                                  before anything else when it can ask.
  --desktop cinnamon|gnome|xfce|mate|plasma|other
                                  Which desktop to theme. It decides where the
                                  theme is written: Cinnamon, GNOME and MATE
                                  each keep it in gsettings under a schema of
                                  their own, Xfce in xfconf, and anything else
                                  in GTK's own settings.ini. Omit it and the
                                  script detects it and offers that as the
                                  default.
  --lang da|nb|sv|fi|de|en        Language, keyboard and timezone in one go.
                                  Omit it and the script asks.
  --ui-lang CODE                  Language for this script's own output.
                                  Defaults to --lang; falls back to English
                                  where no translation exists (fi).
  --keyboard LAYOUT               Override the keyboard layout (e.g. dk, no, us).
                                  Omit it and the script asks, offering the
                                  one that goes with your language.
  --kb-variant NAME               Keyboard variant, e.g. nodeadkeys or intl.
  --timezone ZONE                 Set the timezone and skip the question
                                  (e.g. Europe/Oslo). Omit it and the script
                                  asks, offering the one that goes with your
                                  language.
  --style win11|win10|mac|arc|orchis|colloid|graphite|nordic|mint|none
                                  Look. Omit it and the script asks.
                                    win11    Fluent, rounded and modern
                                    win10    flat and square
                                    mac      WhiteSur
                                    arc      Arc, the classic Linux look
                                    orchis   rounded, material
                                    colloid  clean and quiet
                                    graphite grey, high contrast
                                    nordic   the Nord palette, dark by nature
                                    mint     whatever the system already has
                                    none     do not touch the theme
  --variant light|dark            Light or dark. Omit it and the script asks.
  --layout traditional|win11|mac|mint
                                  Classic taskbar; Windows 11-style centred
                                  taskbar with a grid start menu; macOS menu
                                  bar plus dock; or leave the panel alone.
                                  The panel work needs Cinnamon; on the other
                                  desktops the window buttons and the clock
                                  are still set.
  --menu system|zorin|cinnamenu   Which menu button to put on the panel.
                                  zorin     = the Zorin OS-style menu, which
                                              is ArcMenu - needs GNOME.
                                  cinnamenu = the grid menu - needs Cinnamon.
                                  system    = leave the menu alone.
  --yes                           Do not ask anything; take the defaults.
  --skip-lang                     Do not touch locale/keyboard/language packs
  --skip-theme                    Do not install or apply themes
  --dry-run                       Print what would happen, change nothing
  -h, --help                      This text
      --version                   Print the version and exit

With no options at all it asks for the distribution family first, then the
language, then the keyboard and the timezone that go with it, then which
desktop you are running - it suggests the one it found - and finally the three
look-and-feel questions, defaulting to Windows 11-style, light, with a
traditional taskbar.

On Arch nothing is upgraded: packages are installed from the sync database as
it stands, so run sudo pacman -Syu yourself first if it has gone stale.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --distro)     DISTRO="${2:-}"; shift 2 ;;
    --distro=*)   DISTRO="${1#*=}"; shift ;;
    --desktop)    DESKTOP="${2:-}"; shift 2 ;;
    --desktop=*)  DESKTOP="${1#*=}"; shift ;;
    --lang)       LANG_CHOICE="${2:-}"; shift 2 ;;
    --ui-lang)    UI_LANG="${2:-}"; shift 2 ;;
    --ui-lang=*)  UI_LANG="${1#*=}"; shift ;;
    --lang=*)     LANG_CHOICE="${1#*=}"; shift ;;
    --keyboard)   KEYBOARD="${2:-}"; shift 2 ;;
    --keyboard=*) KEYBOARD="${1#*=}"; shift ;;
    --kb-variant)   KB_VARIANT="${2:-}"; shift 2 ;;
    --kb-variant=*) KB_VARIANT="${1#*=}"; shift ;;
    --timezone)   TIMEZONE="${2:-}"; shift 2 ;;
    --timezone=*) TIMEZONE="${1#*=}"; shift ;;
    --menu)       MENU="${2:-}"; shift 2 ;;
    --menu=*)     MENU="${1#*=}"; shift ;;
    --style)      STYLE="${2:-}"; shift 2 ;;
    --style=*)    STYLE="${1#*=}"; shift ;;
    --variant)    VARIANT="${2:-}"; shift 2 ;;
    --variant=*)  VARIANT="${1#*=}"; shift ;;
    --layout)     LAYOUT="${2:-}"; shift 2 ;;
    --layout=*)   LAYOUT="${1#*=}"; shift ;;
    --panel)      LAYOUT="traditional"; shift ;;   # kept: earlier name for it
    --yes|-y)     ASSUME_YES=1; shift ;;
    --skip-lang)  DO_LANG=0; shift ;;
    --skip-theme) DO_THEME=0; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    --version)    printf 'kasper.sh/linux %s\n' "$SCRIPT_VERSION"; exit 0 ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
done
case "$DISTRO"  in ""|auto) DISTRO="" ;; debian|ubuntu|mint|fedora|arch) ;;
  *) die "--distro must be debian, ubuntu, mint, fedora or arch" ;; esac
case "$DESKTOP" in ""|auto) DESKTOP="" ;; cinnamon|gnome|xfce|mate|plasma|other) ;;
  *) die "--desktop must be cinnamon, gnome, xfce, mate, plasma or other" ;; esac
case "$STYLE"   in ""|win11|win10|mac|arc|orchis|colloid|graphite|nordic|mint|none) ;;
  *) die "--style must be win11, win10, mac, arc, orchis, colloid, graphite, nordic, mint or none" ;; esac
case "$MENU"    in ""|system|zorin|cinnamenu) ;; *) die "--menu must be system, zorin or cinnamenu" ;; esac
case "$VARIANT" in ""|light|dark) ;;           *) die "--variant must be light or dark" ;; esac
case "$LAYOUT"  in ""|traditional|win11|mac|mint|none) ;; *) die "--layout must be traditional, win11, mac or mint" ;; esac

# printf against a message from the catalogue above.
fmt() { printf "$@"; }

# ---------- messages ---------------------------------------------------------
# English is the base and every language only overrides what it has, so a string
# a translation happens to miss comes out in English rather than empty.
set_messages() {
  S_PREFLIGHT="Preflight"
  S_LANG="Language, keyboard and timezone (%s)"
  S_PACKS="Language packs (%s)"
  S_THEME="Desktop theme (%s, %s)"
  S_CLASSIC="Classic desktop"
  S_WIN11="Windows 11-style desktop"
  S_MAC="macOS-style desktop"
  S_DONE="Done"

  M_DETECTED="Detected: %s"
  M_LIVE1="This looks like a live USB session."
  M_LIVE2="Nothing done here survives a reboot - install the system to the disk first."
  M_PREOK="Preflight passed"
  M_INSTALLED="Installed: %s"
  M_PKGFAIL="Could not install: %s - continuing"
  M_SKIPPED="Not in the archive, skipped: %s"
  M_LOCALE="Language: %s (English kept as fallback)"
  M_TZ="Timezone: %s"
  M_KB="Keyboard: %s"
  M_KBWRITE="write /etc/default/keyboard with XKBLAYOUT=\"%s\""
  M_LANGWRITE="write LANGUAGE=%s into %s"
  M_LOCALEFAIL="Could not set the language to %s - continuing"
  M_KBFAIL="dpkg-reconfigure keyboard-configuration failed"
  M_PKGUPD="The package list could not be refreshed - continuing with what is on disk"
  M_PACSYNC="Arch is upgraded as a whole, not in parts - run sudo pacman -Syu yourself if the list is old"
  M_LOCALEGEN="add %s to /etc/locale.gen and run locale-gen"
  M_LOCALEGENFAIL="locale-gen could not build %s"
  M_MINTTHEME="Using the system's own theme"
  M_BIGTHEME="WhiteSur is a large theme - this takes a minute or two."
  M_THEMEFAIL="%s installation failed"
  M_CLONEFAIL="Could not fetch %s - continuing without it"
  M_WOULDSET="Would set theme %s with icons %s"
  M_NOSESS1="No graphical session (over SSH?) - the theme is installed,"
  M_NOSESS2="but you have to pick it under Menu > Themes."
  M_NOTHEME1="The theme was not installed - the desktop is untouched."
  M_NOTHEME2="Try again with a network connection, or pick a theme under Menu > Themes."
  M_NOGTK="%s has no gtk-3.0 part - windows left alone"
  M_STALE1="%s's panel part is from %s and does not style today's Cinnamon."
  M_STALE2="It would leave the taskbar grey - using Mint's own panel theme instead."
  M_NOCINN="%s has no Cinnamon part - using Mint's own panel theme"
  M_NOPANEL="Found no usable panel theme - the panel is untouched"
  M_NOICONS="Icon theme %s was not found"
  M_THEMESET="Theme set: %s, panel: %s, icons: %s"
  M_UNTOUCHED="untouched"
  M_CLASSICOK="Taskbar at the bottom, 24-hour clock, window buttons on the right"
  M_CINNAMENU="Fetched the grid menu Cinnamenu"
  M_NOCINNAMENU="Could not fetch Cinnamenu - keeping Mint's own menu"
  M_NOAPPLETS="Could not read the panel's applets - menu and panel unchanged"
  M_WIN11OK="Icons centred, grid menu, window buttons on the right"
  M_GETMENU="fetch the Cinnamenu applet and switch to it"
  M_MOVEMENU="move menu and window list to the centre of the panel"
  M_MOVEPANEL="move the panel to the top and make it thin"
  M_NOPANELCFG="Could not read the panel setup - move it yourself under Panel settings"
  M_WRITEAUTO="write ~/.config/autostart/plank.desktop"
  M_DOCKOK="Dock set up - it starts with the desktop"
  M_NOPLANK="plank could not be installed - no dock, but the rest is set up"
  M_MACOK="Menu bar on top, dock at the bottom, window buttons on the left"

  M_DEFAULT="(default)"
  M_CHOICE="Choice [%s]: "
  Q_LOOK="How should the desktop look?"
  Q_LOOK1="Like Windows 11  - rounded and modern (Fluent)"
  Q_LOOK2="Like Windows 10  - flat and square"
  Q_LOOK3="Like macOS       - light and soft (WhiteSur)"
  Q_LOOK4="Arc              - the classic Linux look"
  Q_LOOK5="Orchis           - rounded and material"
  Q_LOOK6="Colloid          - clean and quiet"
  Q_LOOK7="Graphite         - grey, high contrast"
  Q_LOOK8="Nordic           - the Nord palette, dark by nature"
  Q_LOOK9="The system's own - Mint-Y or Adwaita, already there"
  Q_LOOK10="Leave the theme  - do not change it"
  Q_LIGHT="Light or dark?"
  Q_LIGHT1="Light"
  Q_LIGHT2="Dark"
  Q_LAYOUT="How should the desktop behave?"
  Q_LAYOUT1="Classic       - taskbar at the bottom, menu in the left corner"
  Q_LAYOUT2="Windows 11    - icons in the middle and a modern grid menu"
  Q_LAYOUT3="macOS         - thin menu bar on top and a dock at the bottom"
  Q_LAYOUT4="Leave it alone - do not touch the panel"

  D_DONE1="Log out and back in for the language, keyboard and panel position to"
  D_DONE2="take full effect. The theme is applied already."
  D_DONE3="Changed your mind? Menu > Themes puts it all back."
  D_DONE4="Want another look? Run the command again and choose differently:"
  D_DONE5="Check afterwards with:"
  S_SUMMARY="This is what you picked"
  L_DISTRO="System"
  L_DESKTOP="Desktop"
  L_LANG="Language"
  L_KB="Keyboard"
  L_TZ="Timezone"
  L_THEME="Theme"
  L_LAYOUT="Layout"
  L_MENU="Menu"
  Q_GO="Go ahead?"
  Q_GO1="Yes - do it"
  Q_GO2="No - stop, change nothing"
  M_ABORT="Stopped. Nothing was changed."
  M_LOGGED="Written down in %s"
  Q_KB="Which keyboard?"
  Q_KB1="The one that goes with %s  - %s"
  Q_KBOTHER="Another            - type the code yourself"
  M_KBASK="Layout code (for example us, de, fr): "
  M_KBUNKNOWN="%s is not a layout this system knows - keeping %s"
  Q_TZ="Which timezone?"
  Q_TZ1="The one that goes with %s  - %s"
  Q_TZOTHER="Another             - type the name yourself"
  M_TZASK="Timezone name (for example Europe/Oslo): "
  M_TZUNKNOWN="%s is not a timezone this system knows - keeping %s"
  M_TZFAIL="Could not set the timezone to %s - continuing"
  S_MENU="Menu button"
  Q_MENU="Which menu button?"
  Q_MENU1="The system's own - leave the menu alone"
  Q_MENU2="Zorin OS-style   - ArcMenu, needs GNOME"
  Q_MENU3="Grid menu        - Cinnamenu, needs Cinnamon"
  M_MENUWRONG="%s cannot take that menu - keeping the one it has"
  M_ARCMENU="Zorin OS-style menu installed (ArcMenu)"
  M_ARCMENUFAIL="ArcMenu could not be built - keeping the menu you have"
  M_ARCICON="Menu button icon: %s - the desktop's own, not the extension's logo"
  M_ARCOLD="ArcMenu is built for GNOME %s and this is %s - installing anyway, it may not load"
  M_ARCENABLE="install ArcMenu and switch its layout to the Zorin OS one"
  M_ARCNOENABLE="Could not switch the extension on - do it under Extensions"
  M_DESKSET="Desktop: %s"
  M_DESKFOUND="Found the desktop: %s"
  M_NOSHELL="%s has no panel theme to set - windows and icons are done"
  M_DESKPANEL="%s has no panel this script can set up - the window buttons are set anyway"
  M_DESKNONE="%s: only the theme is set - the panel and the window buttons stay as they are"
  M_BUTTONS_R="Window buttons on the right"
  M_BUTTONS_L="Window buttons on the left"
  M_NOAPPLY="Could not reach %s's settings - the theme is installed, pick it yourself"
  Q_DESKTOP="Which desktop are you running?"
  Q_DESK1="Cinnamon    - Linux Mint's own, and a Fedora spin"
  Q_DESK2="GNOME       - what Fedora ships by default"
  Q_DESK3="Xfce        - light and classic"
  Q_DESK4="MATE        - the classic GNOME 2 desktop"
  Q_DESK5="KDE Plasma  - GTK apps only; Plasma's own look is left alone"
  Q_DESK6="Something else / not sure - only install the theme"
  M_GSETFAIL="could not set %s %s"
  M_DISTROMISMATCH="Continuing as %s, even though the machine looks like something else"

  case "$1" in
    da)
      S_PREFLIGHT="Forberedelse"
      S_LANG="Sprog, tastatur og tidszone (%s)"
      S_PACKS="Sprogpakker (%s)"
      S_THEME="Skrivebordstema (%s, %s)"
      S_CLASSIC="Klassisk skrivebord"
      S_WIN11="Windows 11-agtigt skrivebord"
      S_MAC="macOS-agtigt skrivebord"
      S_DONE="Færdig"
      M_DETECTED="Fandt: %s"
      M_LIVE1="Det her ligner en live-USB."
      M_LIVE2="Intet af det her overlever en genstart - installér systemet på disken først."
      M_PREOK="Alt klar"
      M_INSTALLED="Installeret: %s"
      M_PKGFAIL="Kunne ikke installere: %s - fortsætter"
      M_SKIPPED="Findes ikke i arkivet, sprunget over: %s"
      M_LOCALE="Sprog: %s (engelsk beholdes som reserve)"
      M_TZ="Tidszone: %s"
      M_KB="Tastatur: %s"
      M_KBWRITE="skriv /etc/default/keyboard med XKBLAYOUT=\"%s\""
      M_LANGWRITE="skriv LANGUAGE=%s i %s"
      M_LOCALEFAIL="Kunne ikke sætte sproget til %s - fortsætter"
      M_KBFAIL="dpkg-reconfigure keyboard-configuration fejlede"
      M_PKGUPD="Pakkelisten kunne ikke opdateres - fortsætter med den, der ligger på disken"
      M_PACSYNC="Arch opdateres som en helhed, ikke stykvis - kør selv sudo pacman -Syu, hvis listen er gammel"
      M_LOCALEGEN="skriv %s i /etc/locale.gen og kør locale-gen"
      M_LOCALEGENFAIL="locale-gen kunne ikke bygge %s"
      M_MINTTHEME="Bruger systemets eget tema"
      M_BIGTHEME="WhiteSur er et stort tema - det tager et minut eller to."
      M_THEMEFAIL="Installationen af %s fejlede"
      M_CLONEFAIL="Kunne ikke hente %s - fortsætter uden"
      M_WOULDSET="Ville sætte temaet %s med ikonerne %s"
      M_NOSESS1="Ingen grafisk session (kører du over SSH?) - temaet er installeret,"
      M_NOSESS2="men du skal selv vælge det under Menu > Temaer."
      M_NOTHEME1="Temaet blev ikke installeret - skrivebordet er urørt."
      M_NOTHEME2="Prøv igen med netforbindelse, eller vælg et tema under Menu > Temaer."
      M_NOGTK="%s har ingen gtk-3.0-del - vinduerne er urørt"
      M_STALE1="Paneldelen i %s er fra %s og styler ikke nutidens Cinnamon."
      M_STALE2="Den ville gøre proceslinjen grå - bruger Mints eget paneltema i stedet."
      M_NOCINN="%s har ingen Cinnamon-del - bruger Mints eget paneltema"
      M_NOPANEL="Fandt intet brugbart paneltema - panelet er urørt"
      M_NOICONS="Ikontemaet %s blev ikke fundet"
      M_THEMESET="Tema sat: %s, panel: %s, ikoner: %s"
      M_UNTOUCHED="urørt"
      M_CLASSICOK="Proceslinje forneden, 24-timers ur, vinduesknapper til højre"
      M_CINNAMENU="Hentede gittermenuen Cinnamenu"
      M_NOCINNAMENU="Kunne ikke hente Cinnamenu - beholder Mints egen menu"
      M_NOAPPLETS="Kunne ikke læse panelets applets - menu og panel er uændret"
      M_WIN11OK="Ikoner i midten, gittermenu, vinduesknapper til højre"
      M_GETMENU="hent Cinnamenu-appletten og skift til den"
      M_MOVEMENU="flyt menu og vindueliste til midten af panelet"
      M_MOVEPANEL="flyt panelet til toppen og gør det tyndt"
      M_NOPANELCFG="Kunne ikke læse panelets opsætning - flyt det selv under Panelindstillinger"
      M_WRITEAUTO="skriv ~/.config/autostart/plank.desktop"
      M_DOCKOK="Dock sat op - den starter sammen med skrivebordet"
      M_NOPLANK="plank kunne ikke installeres - ingen dock, men resten er sat op"
      M_MACOK="Menulinje foroven, dock forneden, vinduesknapper til venstre"
      M_DEFAULT="(standard)"
      M_CHOICE="Valg [%s]: "
      Q_LOOK="Hvordan skal skrivebordet se ud?"
      Q_LOOK1="Som Windows 11   - afrundet og moderne (Fluent)"
      Q_LOOK2="Som Windows 10   - fladt og firkantet"
      Q_LOOK3="Som macOS        - lyst og blødt (WhiteSur)"
      Q_LOOK4="Arc              - det klassiske Linux-look"
      Q_LOOK5="Orchis           - rundt og materialeagtigt"
      Q_LOOK6="Colloid          - rent og roligt"
      Q_LOOK7="Graphite         - gråt med skarp kontrast"
      Q_LOOK8="Nordic           - Nord-paletten, mørk af natur"
      Q_LOOK9="Systemets eget   - Mint-Y eller Adwaita, allerede der"
      Q_LOOK10="Lad temaet være  - skift det ikke"
      Q_LIGHT="Lyst eller mørkt?"
      Q_LIGHT1="Lyst"
      Q_LIGHT2="Mørkt"
      Q_LAYOUT="Hvordan skal skrivebordet opføre sig?"
      Q_LAYOUT1="Klassisk        - proceslinje forneden, menu i venstre hjørne"
      Q_LAYOUT2="Som Windows 11  - ikoner i midten og en moderne gittermenu"
      Q_LAYOUT3="Som macOS       - tynd menulinje foroven og en dock forneden"
      Q_LAYOUT4="Lad det være    - rør ikke ved panelet"
      D_DONE1="Log ud og ind igen, så slår sproget, tastaturet og panelets placering"
      D_DONE2="helt igennem. Temaet er sat med det samme."
      D_DONE3="Fortryder du? Menu > Temaer skifter det hele tilbage."
      D_DONE4="Vil du prøve et andet look, så kør kommandoen igen og vælg noget andet:"
      D_DONE5="Tjek bagefter med:"
      S_SUMMARY="Det her har du valgt"
      L_DISTRO="System"
      L_DESKTOP="Skrivebord"
      L_LANG="Sprog"
      L_KB="Tastatur"
      L_TZ="Tidszone"
      L_THEME="Tema"
      L_LAYOUT="Opsætning"
      L_MENU="Menu"
      Q_GO="Skal den køre?"
      Q_GO1="Ja - sæt i gang"
      Q_GO2="Nej - stop, ændr ingenting"
      M_ABORT="Stoppet. Der er ikke ændret noget."
      M_LOGGED="Skrevet ned i %s"
      Q_KB="Hvilket tastatur?"
      Q_KB1="Det, der følger %s  - %s"
      Q_KBOTHER="Et andet          - skriv koden selv"
      M_KBASK="Tastaturkode (for eksempel us, de, fr): "
      M_KBUNKNOWN="%s er ikke et tastatur, maskinen kender - beholder %s"
      Q_TZ="Hvilken tidszone?"
      Q_TZ1="Den, der følger %s  - %s"
      Q_TZOTHER="En anden           - skriv navnet selv"
      M_TZASK="Tidszonens navn (for eksempel Europe/Copenhagen): "
      M_TZUNKNOWN="%s er ikke en tidszone, maskinen kender - beholder %s"
      M_TZFAIL="Kunne ikke sætte tidszonen til %s - fortsætter"
      S_MENU="Menuknap"
      Q_MENU="Hvilken menuknap?"
      Q_MENU1="Systemets egen   - lad menuen være"
      Q_MENU2="Som Zorin OS     - ArcMenu, kræver GNOME"
      Q_MENU3="Gittermenu       - Cinnamenu, kræver Cinnamon"
      M_MENUWRONG="%s kan ikke tage den menu - beholder den, der er"
      M_ARCMENU="Zorin OS-agtig menu installeret (ArcMenu)"
      M_ARCMENUFAIL="ArcMenu kunne ikke bygges - beholder den menu, du har"
      M_ARCICON="Menuknappens ikon: %s - skrivebordets eget, ikke udvidelsens logo"
      M_ARCOLD="ArcMenu er bygget til GNOME %s, og her er %s - installerer alligevel, den indlæses måske ikke"
      M_ARCENABLE="installér ArcMenu og skift dens opsætning til Zorin OS-udgaven"
      M_ARCNOENABLE="Kunne ikke slå udvidelsen til - gør det selv under Udvidelser"
      M_DESKSET="Skrivebord: %s"
      M_DESKFOUND="Fandt skrivebordet: %s"
      M_NOSHELL="%s har intet paneltema at sætte - vinduer og ikoner er på plads"
      M_DESKPANEL="%s har intet panel, scriptet kan sætte op - vinduesknapperne er sat alligevel"
      M_DESKNONE="%s: kun temaet er sat - panelet og vinduesknapperne står, som de står"
      M_BUTTONS_R="Vinduesknapper til højre"
      M_BUTTONS_L="Vinduesknapper til venstre"
      M_NOAPPLY="Kunne ikke nå indstillingerne i %s - temaet er installeret, vælg det selv"
      Q_DESKTOP="Hvilket skrivebord kører du?"
      Q_DESK1="Cinnamon    - Linux Mints eget, og en Fedora-udgave"
      Q_DESK2="GNOME       - det, Fedora leverer som standard"
      Q_DESK3="Xfce        - let og klassisk"
      Q_DESK4="MATE        - det klassiske GNOME 2-skrivebord"
      Q_DESK5="KDE Plasma  - kun GTK-programmer; Plasmas eget udseende røres ikke"
      Q_DESK6="Noget andet / ved ikke - installér kun temaet"
      M_GSETFAIL="kunne ikke sætte %s %s"
      M_DISTROMISMATCH="Fortsætter som %s, selvom maskinen ligner noget andet"
      ;;
    nb)
      S_PREFLIGHT="Forberedelse"
      S_LANG="Språk, tastatur og tidssone (%s)"
      S_PACKS="Språkpakker (%s)"
      S_THEME="Skrivebordstema (%s, %s)"
      S_CLASSIC="Klassisk skrivebord"
      S_WIN11="Windows 11-aktig skrivebord"
      S_MAC="macOS-aktig skrivebord"
      S_DONE="Ferdig"
      M_DETECTED="Fant: %s"
      M_LIVE1="Dette ser ut som en live-USB."
      M_LIVE2="Ingenting her overlever en omstart - installer systemet på disken først."
      M_PREOK="Alt klart"
      M_INSTALLED="Installert: %s"
      M_PKGFAIL="Klarte ikke å installere: %s - fortsetter"
      M_SKIPPED="Finnes ikke i arkivet, hoppet over: %s"
      M_LOCALE="Språk: %s (engelsk beholdes som reserve)"
      M_TZ="Tidssone: %s"
      M_KB="Tastatur: %s"
      M_KBFAIL="dpkg-reconfigure keyboard-configuration feilet"
      M_KBWRITE="skriv /etc/default/keyboard med XKBLAYOUT=\"%s\""
      M_LANGWRITE="skriv LANGUAGE=%s i %s"
      M_LOCALEFAIL="Klarte ikke å sette språket til %s - fortsetter"
      M_PKGUPD="Pakkelisten kunne ikke oppdateres - fortsetter med den som ligger på disken"
      M_PACSYNC="Arch oppdateres som en helhet, ikke stykkevis - kjør sudo pacman -Syu selv hvis listen er gammel"
      M_LOCALEGEN="skriv %s i /etc/locale.gen og kjør locale-gen"
      M_LOCALEGENFAIL="locale-gen kunne ikke bygge %s"
      M_MINTTHEME="Bruker systemets eget tema"
      M_BIGTHEME="WhiteSur er et stort tema - det tar et minutt eller to."
      M_THEMEFAIL="Installasjonen av %s feilet"
      M_CLONEFAIL="Klarte ikke å hente %s - fortsetter uten"
      M_WOULDSET="Ville satt temaet %s med ikonene %s"
      M_NOSESS1="Ingen grafisk økt (kjører du over SSH?) - temaet er installert,"
      M_NOSESS2="men du må velge det selv under Meny > Tema."
      M_NOTHEME1="Temaet ble ikke installert - skrivebordet er urørt."
      M_NOTHEME2="Prøv igjen med nettforbindelse, eller velg et tema under Meny > Tema."
      M_NOGTK="%s har ingen gtk-3.0-del - vinduene er urørt"
      M_STALE1="Paneldelen i %s er fra %s og styler ikke dagens Cinnamon."
      M_STALE2="Den ville gjort oppgavelinjen grå - bruker Mints eget paneltema i stedet."
      M_NOCINN="%s har ingen Cinnamon-del - bruker Mints eget paneltema"
      M_NOPANEL="Fant ingen brukbare paneltema - panelet er urørt"
      M_NOICONS="Ikontemaet %s ble ikke funnet"
      M_THEMESET="Tema satt: %s, panel: %s, ikoner: %s"
      M_UNTOUCHED="urørt"
      M_CLASSICOK="Oppgavelinje nederst, 24-timers klokke, vindusknapper til høyre"
      M_CINNAMENU="Hentet rutenettmenyen Cinnamenu"
      M_NOCINNAMENU="Klarte ikke å hente Cinnamenu - beholder Mints egen meny"
      M_NOAPPLETS="Klarte ikke å lese panelets appleter - meny og panel er uendret"
      M_WIN11OK="Ikoner i midten, rutenettmeny, vindusknapper til høyre"
      M_GETMENU="hent Cinnamenu-appleten og bytt til den"
      M_MOVEMENU="flytt meny og vindusliste til midten av panelet"
      M_MOVEPANEL="flytt panelet til toppen og gjør det tynt"
      M_WRITEAUTO="skriv ~/.config/autostart/plank.desktop"
      M_NOPANELCFG="Klarte ikke å lese panelets oppsett - flytt det selv under Panelinnstillinger"
      M_DOCKOK="Dock satt opp - den starter sammen med skrivebordet"
      M_NOPLANK="plank kunne ikke installeres - ingen dock, men resten er satt opp"
      M_MACOK="Menylinje øverst, dock nederst, vindusknapper til venstre"
      M_DEFAULT="(standard)"
      M_CHOICE="Valg [%s]: "
      Q_LOOK="Hvordan skal skrivebordet se ut?"
      Q_LOOK1="Som Windows 11   - avrundet og moderne (Fluent)"
      Q_LOOK2="Som Windows 10   - flatt og firkantet"
      Q_LOOK3="Som macOS        - lyst og mykt (WhiteSur)"
      Q_LOOK4="Arc              - det klassiske Linux-utseendet"
      Q_LOOK5="Orchis           - rundt og materialeaktig"
      Q_LOOK6="Colloid          - rent og rolig"
      Q_LOOK7="Graphite         - grått med skarp kontrast"
      Q_LOOK8="Nordic           - Nord-paletten, mørk av natur"
      Q_LOOK9="Systemets eget   - Mint-Y eller Adwaita, allerede der"
      Q_LOOK10="La temaet være   - ikke endre det"
      Q_LIGHT="Lyst eller mørkt?"
      Q_LIGHT1="Lyst"
      Q_LIGHT2="Mørkt"
      Q_LAYOUT="Hvordan skal skrivebordet oppføre seg?"
      Q_LAYOUT1="Klassisk        - oppgavelinje nederst, meny i venstre hjørne"
      Q_LAYOUT2="Som Windows 11  - ikoner i midten og en moderne rutenettmeny"
      Q_LAYOUT3="Som macOS       - tynn menylinje øverst og en dock nederst"
      Q_LAYOUT4="La det være     - ikke rør panelet"
      D_DONE1="Logg ut og inn igjen, så slår språket, tastaturet og panelets plassering"
      D_DONE2="helt igjennom. Temaet er satt med en gang."
      D_DONE3="Angrer du? Meny > Tema setter alt tilbake."
      D_DONE4="Vil du prøve et annet utseende, kjør kommandoen igjen og velg noe annet:"
      D_DONE5="Sjekk etterpå med:"
      S_SUMMARY="Dette har du valgt"
      L_DISTRO="System"
      L_DESKTOP="Skrivebord"
      L_LANG="Språk"
      L_KB="Tastatur"
      L_TZ="Tidssone"
      L_THEME="Tema"
      L_LAYOUT="Oppsett"
      L_MENU="Meny"
      Q_GO="Skal den kjøre?"
      Q_GO1="Ja - sett i gang"
      Q_GO2="Nei - stopp, ikke endre noe"
      M_ABORT="Stoppet. Ingenting er endret."
      M_LOGGED="Skrevet ned i %s"
      Q_KB="Hvilket tastatur?"
      Q_KB1="Det som følger %s  - %s"
      Q_KBOTHER="Et annet          - skriv koden selv"
      M_KBASK="Tastaturkode (for eksempel us, de, fr): "
      M_KBUNKNOWN="%s er ikke et tastatur maskinen kjenner - beholder %s"
      Q_TZ="Hvilken tidssone?"
      Q_TZ1="Den som følger %s  - %s"
      Q_TZOTHER="En annen           - skriv navnet selv"
      M_TZASK="Tidssonens navn (for eksempel Europe/Oslo): "
      M_TZUNKNOWN="%s er ikke en tidssone maskinen kjenner - beholder %s"
      M_TZFAIL="Klarte ikke å sette tidssonen til %s - fortsetter"
      S_MENU="Menyknapp"
      Q_MENU="Hvilken menyknapp?"
      Q_MENU1="Systemets egen   - la menyen være"
      Q_MENU2="Som Zorin OS     - ArcMenu, krever GNOME"
      Q_MENU3="Rutenettmeny     - Cinnamenu, krever Cinnamon"
      M_MENUWRONG="%s kan ikke ta den menyen - beholder den som er"
      M_ARCMENU="Zorin OS-aktig meny installert (ArcMenu)"
      M_ARCMENUFAIL="ArcMenu kunne ikke bygges - beholder menyen du har"
      M_ARCICON="Menyknappens ikon: %s - skrivebordets eget, ikke utvidelsens logo"
      M_ARCOLD="ArcMenu er bygget for GNOME %s, og her er %s - installerer likevel, den lastes kanskje ikke"
      M_ARCENABLE="installer ArcMenu og bytt oppsettet til Zorin OS-utgaven"
      M_ARCNOENABLE="Klarte ikke å slå på utvidelsen - gjør det selv under Utvidelser"
      M_DESKSET="Skrivebord: %s"
      M_DESKFOUND="Fant skrivebordet: %s"
      M_NOSHELL="%s har ikke noe paneltema å sette - vinduer og ikoner er på plass"
      M_DESKPANEL="%s har ikke noe panel skriptet kan sette opp - vindusknappene er satt likevel"
      M_DESKNONE="%s: bare temaet er satt - panelet og vindusknappene står som de står"
      M_BUTTONS_R="Vindusknapper til høyre"
      M_BUTTONS_L="Vindusknapper til venstre"
      M_NOAPPLY="Nådde ikke innstillingene i %s - temaet er installert, velg det selv"
      Q_DESKTOP="Hvilket skrivebord kjører du?"
      Q_DESK1="Cinnamon    - Linux Mints eget, og en Fedora-utgave"
      Q_DESK2="GNOME       - det Fedora leverer som standard"
      Q_DESK3="Xfce        - lett og klassisk"
      Q_DESK4="MATE        - det klassiske GNOME 2-skrivebordet"
      Q_DESK5="KDE Plasma  - bare GTK-programmer; Plasmas eget utseende røres ikke"
      Q_DESK6="Noe annet / vet ikke - installer bare temaet"
      M_GSETFAIL="klarte ikke å sette %s %s"
      M_DISTROMISMATCH="Fortsetter som %s, selv om maskinen ligner noe annet"
      ;;
    sv)
      S_PREFLIGHT="Förberedelse"
      S_LANG="Språk, tangentbord och tidszon (%s)"
      S_PACKS="Språkpaket (%s)"
      S_THEME="Skrivbordstema (%s, %s)"
      S_CLASSIC="Klassiskt skrivbord"
      S_WIN11="Windows 11-liknande skrivbord"
      S_MAC="macOS-liknande skrivbord"
      S_DONE="Klart"
      M_DETECTED="Hittade: %s"
      M_LIVE1="Det här ser ut som en live-USB."
      M_LIVE2="Inget här överlever en omstart - installera systemet på disken först."
      M_PREOK="Allt klart"
      M_INSTALLED="Installerat: %s"
      M_PKGFAIL="Kunde inte installera: %s - fortsätter"
      M_SKIPPED="Finns inte i arkivet, hoppade över: %s"
      M_LOCALE="Språk: %s (engelska behålls som reserv)"
      M_TZ="Tidszon: %s"
      M_KB="Tangentbord: %s"
      M_KBFAIL="dpkg-reconfigure keyboard-configuration misslyckades"
      M_KBWRITE="skriv /etc/default/keyboard med XKBLAYOUT=\"%s\""
      M_LANGWRITE="skriv LANGUAGE=%s i %s"
      M_LOCALEFAIL="Kunde inte ställa in språket till %s - fortsätter"
      M_PKGUPD="Paketlistan kunde inte uppdateras - fortsätter med den som finns på disken"
      M_PACSYNC="Arch uppdateras som en helhet, inte i delar - kör sudo pacman -Syu själv om listan är gammal"
      M_LOCALEGEN="skriv %s i /etc/locale.gen och kör locale-gen"
      M_LOCALEGENFAIL="locale-gen kunde inte bygga %s"
      M_MINTTHEME="Använder systemets eget tema"
      M_BIGTHEME="WhiteSur är ett stort tema - det tar en minut eller två."
      M_THEMEFAIL="Installationen av %s misslyckades"
      M_CLONEFAIL="Kunde inte hämta %s - fortsätter utan"
      M_WOULDSET="Skulle sätta temat %s med ikonerna %s"
      M_NOSESS1="Ingen grafisk session (kör du över SSH?) - temat är installerat,"
      M_NOSESS2="men du måste välja det själv under Meny > Teman."
      M_NOTHEME1="Temat installerades inte - skrivbordet är orört."
      M_NOTHEME2="Försök igen med nätverk, eller välj ett tema under Meny > Teman."
      M_NOGTK="%s har ingen gtk-3.0-del - fönstren är orörda"
      M_STALE1="Paneldelen i %s är från %s och stylar inte dagens Cinnamon."
      M_STALE2="Den skulle göra aktivitetsfältet grått - använder Mints eget paneltema i stället."
      M_NOCINN="%s har ingen Cinnamon-del - använder Mints eget paneltema"
      M_NOPANEL="Hittade inget användbart paneltema - panelen är orörd"
      M_NOICONS="Ikontemat %s hittades inte"
      M_THEMESET="Tema satt: %s, panel: %s, ikoner: %s"
      M_UNTOUCHED="orörd"
      M_CLASSICOK="Aktivitetsfält nedtill, 24-timmarsklocka, fönsterknappar till höger"
      M_CINNAMENU="Hämtade rutnätsmenyn Cinnamenu"
      M_NOCINNAMENU="Kunde inte hämta Cinnamenu - behåller Mints egen meny"
      M_NOAPPLETS="Kunde inte läsa panelens appletar - meny och panel oförändrade"
      M_WIN11OK="Ikoner i mitten, rutnätsmeny, fönsterknappar till höger"
      M_GETMENU="hämta Cinnamenu-appleten och byt till den"
      M_MOVEMENU="flytta meny och fönsterlista till mitten av panelen"
      M_MOVEPANEL="flytta panelen till toppen och gör den tunn"
      M_WRITEAUTO="skriv ~/.config/autostart/plank.desktop"
      M_NOPANELCFG="Kunde inte läsa panelens inställningar - flytta den själv under Panelinställningar"
      M_DOCKOK="Docka uppsatt - den startar med skrivbordet"
      M_NOPLANK="plank kunde inte installeras - ingen docka, men resten är uppsatt"
      M_MACOK="Menyrad upptill, docka nedtill, fönsterknappar till vänster"
      M_DEFAULT="(standard)"
      M_CHOICE="Val [%s]: "
      Q_LOOK="Hur ska skrivbordet se ut?"
      Q_LOOK1="Som Windows 11   - rundat och modernt (Fluent)"
      Q_LOOK2="Som Windows 10   - platt och kantigt"
      Q_LOOK3="Som macOS        - ljust och mjukt (WhiteSur)"
      Q_LOOK4="Arc              - det klassiska Linux-utseendet"
      Q_LOOK5="Orchis           - runt och materialaktigt"
      Q_LOOK6="Colloid          - rent och lugnt"
      Q_LOOK7="Graphite         - grått med skarp kontrast"
      Q_LOOK8="Nordic           - Nord-paletten, mörk av naturen"
      Q_LOOK9="Systemets eget   - Mint-Y eller Adwaita, redan där"
      Q_LOOK10="Låt temat vara   - ändra det inte"
      Q_LIGHT="Ljust eller mörkt?"
      Q_LIGHT1="Ljust"
      Q_LIGHT2="Mörkt"
      Q_LAYOUT="Hur ska skrivbordet bete sig?"
      Q_LAYOUT1="Klassiskt       - aktivitetsfält nedtill, meny i vänstra hörnet"
      Q_LAYOUT2="Som Windows 11  - ikoner i mitten och en modern rutnätsmeny"
      Q_LAYOUT3="Som macOS       - tunn menyrad upptill och en docka nedtill"
      Q_LAYOUT4="Låt det vara    - rör inte panelen"
      D_DONE1="Logga ut och in igen, så slår språket, tangentbordet och panelens placering"
      D_DONE2="igenom helt. Temat är satt direkt."
      D_DONE3="Ångrar du dig? Meny > Teman ställer tillbaka allt."
      D_DONE4="Vill du prova ett annat utseende? Kör kommandot igen och välj något annat:"
      D_DONE5="Kolla efteråt med:"
      S_SUMMARY="Det här har du valt"
      L_DISTRO="System"
      L_DESKTOP="Skrivbord"
      L_LANG="Språk"
      L_KB="Tangentbord"
      L_TZ="Tidszon"
      L_THEME="Tema"
      L_LAYOUT="Upplägg"
      L_MENU="Meny"
      Q_GO="Ska den köras?"
      Q_GO1="Ja - sätt igång"
      Q_GO2="Nej - stoppa, ändra ingenting"
      M_ABORT="Stoppad. Ingenting ändrades."
      M_LOGGED="Nedskrivet i %s"
      Q_KB="Vilket tangentbord?"
      Q_KB1="Det som följer %s  - %s"
      Q_KBOTHER="Ett annat         - skriv koden själv"
      M_KBASK="Tangentbordskod (till exempel us, de, fr): "
      M_KBUNKNOWN="%s är inget tangentbord maskinen känner till - behåller %s"
      Q_TZ="Vilken tidszon?"
      Q_TZ1="Den som följer %s  - %s"
      Q_TZOTHER="En annan           - skriv namnet själv"
      M_TZASK="Tidszonens namn (till exempel Europe/Stockholm): "
      M_TZUNKNOWN="%s är ingen tidszon maskinen känner till - behåller %s"
      M_TZFAIL="Kunde inte ställa in tidszonen till %s - fortsätter"
      S_MENU="Menyknapp"
      Q_MENU="Vilken menyknapp?"
      Q_MENU1="Systemets egen   - låt menyn vara"
      Q_MENU2="Som Zorin OS     - ArcMenu, kräver GNOME"
      Q_MENU3="Rutnätsmeny      - Cinnamenu, kräver Cinnamon"
      M_MENUWRONG="%s kan inte ta den menyn - behåller den som finns"
      M_ARCMENU="Zorin OS-liknande meny installerad (ArcMenu)"
      M_ARCMENUFAIL="ArcMenu kunde inte byggas - behåller menyn du har"
      M_ARCICON="Menyknappens ikon: %s - skrivbordets egen, inte tilläggets logotyp"
      M_ARCOLD="ArcMenu är byggd för GNOME %s och här är %s - installerar ändå, den kanske inte laddas"
      M_ARCENABLE="installera ArcMenu och byt dess layout till Zorin OS-varianten"
      M_ARCNOENABLE="Kunde inte slå på tillägget - gör det själv under Tillägg"
      M_DESKSET="Skrivbord: %s"
      M_DESKFOUND="Hittade skrivbordet: %s"
      M_NOSHELL="%s har inget paneltema att sätta - fönster och ikoner är klara"
      M_DESKPANEL="%s har ingen panel som skriptet kan ställa in - fönsterknapparna är satta ändå"
      M_DESKNONE="%s: bara temat är satt - panelen och fönsterknapparna står kvar"
      M_BUTTONS_R="Fönsterknappar till höger"
      M_BUTTONS_L="Fönsterknappar till vänster"
      M_NOAPPLY="Nådde inte inställningarna i %s - temat är installerat, välj det själv"
      Q_DESKTOP="Vilket skrivbord kör du?"
      Q_DESK1="Cinnamon    - Linux Mints eget, och en Fedora-utgåva"
      Q_DESK2="GNOME       - det Fedora levererar som standard"
      Q_DESK3="Xfce        - lätt och klassiskt"
      Q_DESK4="MATE        - det klassiska GNOME 2-skrivbordet"
      Q_DESK5="KDE Plasma  - bara GTK-program; Plasmas eget utseende rörs inte"
      Q_DESK6="Något annat / vet inte - installera bara temat"
      M_GSETFAIL="kunde inte sätta %s %s"
      M_DISTROMISMATCH="Fortsätter som %s, även om maskinen ser ut som något annat"
      ;;
    de)
      S_PREFLIGHT="Vorbereitung"
      S_LANG="Sprache, Tastatur und Zeitzone (%s)"
      S_PACKS="Sprachpakete (%s)"
      S_THEME="Desktop-Thema (%s, %s)"
      S_CLASSIC="Klassischer Desktop"
      S_WIN11="Desktop im Windows-11-Stil"
      S_MAC="Desktop im macOS-Stil"
      S_DONE="Fertig"
      M_DETECTED="Gefunden: %s"
      M_LIVE1="Das sieht nach einer Live-USB-Sitzung aus."
      M_LIVE2="Nichts davon übersteht einen Neustart - installieren Sie das System zuerst auf die Platte."
      M_PREOK="Alles bereit"
      M_INSTALLED="Installiert: %s"
      M_PKGFAIL="Konnte nicht installieren: %s - weiter"
      M_SKIPPED="Nicht im Archiv, übersprungen: %s"
      M_LOCALE="Sprache: %s (Englisch bleibt als Rückfall)"
      M_TZ="Zeitzone: %s"
      M_KB="Tastatur: %s"
      M_KBFAIL="dpkg-reconfigure keyboard-configuration fehlgeschlagen"
      M_KBWRITE="/etc/default/keyboard mit XKBLAYOUT=\"%s\" schreiben"
      M_LANGWRITE="LANGUAGE=%s in %s schreiben"
      M_LOCALEFAIL="Konnte die Sprache nicht auf %s setzen - weiter"
      M_PKGUPD="Die Paketliste konnte nicht aktualisiert werden - weiter mit der auf der Platte"
      M_PACSYNC="Arch wird als Ganzes aktualisiert, nicht in Teilen - fuehren Sie sudo pacman -Syu selbst aus, wenn die Liste alt ist"
      M_LOCALEGEN="%s in /etc/locale.gen eintragen und locale-gen ausfuehren"
      M_LOCALEGENFAIL="locale-gen konnte %s nicht erzeugen"
      M_MINTTHEME="Verwende das systemeigene Thema"
      M_BIGTHEME="WhiteSur ist ein großes Thema - das dauert ein bis zwei Minuten."
      M_THEMEFAIL="Installation von %s fehlgeschlagen"
      M_CLONEFAIL="Konnte %s nicht holen - weiter ohne"
      M_WOULDSET="Würde Thema %s mit den Symbolen %s setzen"
      M_NOSESS1="Keine grafische Sitzung (über SSH?) - das Thema ist installiert,"
      M_NOSESS2="Sie müssen es unter Menü > Themen selbst auswählen."
      M_NOTHEME1="Das Thema wurde nicht installiert - der Desktop bleibt unverändert."
      M_NOTHEME2="Mit Netzverbindung erneut versuchen, oder ein Thema unter Menü > Themen wählen."
      M_NOGTK="%s hat keinen gtk-3.0-Teil - Fenster bleiben unverändert"
      M_STALE1="Der Panel-Teil von %s stammt aus %s und passt nicht zum heutigen Cinnamon."
      M_STALE2="Die Leiste würde grau bleiben - verwende stattdessen Mints eigenes Panel-Thema."
      M_NOCINN="%s hat keinen Cinnamon-Teil - verwende Mints eigenes Panel-Thema"
      M_NOPANEL="Kein brauchbares Panel-Thema gefunden - das Panel bleibt unverändert"
      M_NOICONS="Symbolthema %s nicht gefunden"
      M_THEMESET="Thema gesetzt: %s, Panel: %s, Symbole: %s"
      M_UNTOUCHED="unverändert"
      M_CLASSICOK="Leiste unten, 24-Stunden-Uhr, Fensterknöpfe rechts"
      M_CINNAMENU="Rastermenü Cinnamenu geholt"
      M_NOCINNAMENU="Cinnamenu konnte nicht geholt werden - behalte Mints eigenes Menü"
      M_NOAPPLETS="Panel-Applets nicht lesbar - Menü und Panel unverändert"
      M_WIN11OK="Symbole mittig, Rastermenü, Fensterknöpfe rechts"
      M_GETMENU="das Cinnamenu-Applet holen und darauf umstellen"
      M_MOVEMENU="Menü und Fensterliste in die Mitte des Panels verschieben"
      M_MOVEPANEL="das Panel nach oben verschieben und schmal machen"
      M_WRITEAUTO="~/.config/autostart/plank.desktop schreiben"
      M_NOPANELCFG="Panel-Einstellung nicht lesbar - verschieben Sie es selbst unter Panel-Einstellungen"
      M_DOCKOK="Dock eingerichtet - es startet mit dem Desktop"
      M_NOPLANK="plank ließ sich nicht installieren - kein Dock, der Rest steht"
      M_MACOK="Menüleiste oben, Dock unten, Fensterknöpfe links"
      M_DEFAULT="(Standard)"
      M_CHOICE="Auswahl [%s]: "
      Q_LOOK="Wie soll der Desktop aussehen?"
      Q_LOOK1="Wie Windows 11   - abgerundet und modern (Fluent)"
      Q_LOOK2="Wie Windows 10   - flach und kantig"
      Q_LOOK3="Wie macOS        - hell und weich (WhiteSur)"
      Q_LOOK4="Arc              - der klassische Linux-Look"
      Q_LOOK5="Orchis           - rund und materialartig"
      Q_LOOK6="Colloid          - klar und ruhig"
      Q_LOOK7="Graphite         - grau, kontrastreich"
      Q_LOOK8="Nordic           - die Nord-Palette, dunkel von Natur aus"
      Q_LOOK9="Systemeigenes    - Mint-Y oder Adwaita, schon da"
      Q_LOOK10="Thema lassen     - nicht ändern"
      Q_LIGHT="Hell oder dunkel?"
      Q_LIGHT1="Hell"
      Q_LIGHT2="Dunkel"
      Q_LAYOUT="Wie soll sich der Desktop verhalten?"
      Q_LAYOUT1="Klassisch       - Leiste unten, Menü in der linken Ecke"
      Q_LAYOUT2="Wie Windows 11  - Symbole mittig und ein modernes Rastermenü"
      Q_LAYOUT3="Wie macOS       - schmale Menüleiste oben und ein Dock unten"
      Q_LAYOUT4="Unverändert     - das Panel nicht anfassen"
      D_DONE1="Melden Sie sich ab und wieder an, damit Sprache, Tastatur und Panel-Position"
      D_DONE2="voll greifen. Das Thema ist bereits gesetzt."
      D_DONE3="Doch anders? Menü > Themen stellt alles zurück."
      D_DONE4="Anderes Aussehen? Befehl erneut ausführen und anders wählen:"
      D_DONE5="Danach prüfen mit:"
      S_SUMMARY="Das haben Sie gewählt"
      L_DISTRO="System"
      L_DESKTOP="Desktop"
      L_LANG="Sprache"
      L_KB="Tastatur"
      L_TZ="Zeitzone"
      L_THEME="Thema"
      L_LAYOUT="Layout"
      L_MENU="Menü"
      Q_GO="Loslegen?"
      Q_GO1="Ja - ausführen"
      Q_GO2="Nein - abbrechen, nichts ändern"
      M_ABORT="Abgebrochen. Es wurde nichts geändert."
      M_LOGGED="Notiert in %s"
      Q_KB="Welche Tastatur?"
      Q_KB1="Die zu %s passende  - %s"
      Q_KBOTHER="Eine andere       - den Code selbst eingeben"
      M_KBASK="Tastaturcode (zum Beispiel us, de, fr): "
      M_KBUNKNOWN="%s ist keine Tastatur, die dieser Rechner kennt - es bleibt bei %s"
      Q_TZ="Welche Zeitzone?"
      Q_TZ1="Die zu %s passende  - %s"
      Q_TZOTHER="Eine andere        - den Namen selbst eingeben"
      M_TZASK="Name der Zeitzone (zum Beispiel Europe/Berlin): "
      M_TZUNKNOWN="%s ist keine Zeitzone, die dieser Rechner kennt - es bleibt bei %s"
      M_TZFAIL="Konnte die Zeitzone nicht auf %s setzen - weiter"
      S_MENU="Menüknopf"
      Q_MENU="Welcher Menüknopf?"
      Q_MENU1="Der systemeigene - das Menü unangetastet lassen"
      Q_MENU2="Wie Zorin OS     - ArcMenu, braucht GNOME"
      Q_MENU3="Rastermenü       - Cinnamenu, braucht Cinnamon"
      M_MENUWRONG="%s kann dieses Menü nicht übernehmen - es bleibt beim jetzigen"
      M_ARCMENU="Menü im Zorin-OS-Stil installiert (ArcMenu)"
      M_ARCMENUFAIL="ArcMenu ließ sich nicht bauen - es bleibt beim jetzigen Menü"
      M_ARCICON="Symbol des Menüknopfs: %s - das des Desktops, nicht das Logo der Erweiterung"
      M_ARCOLD="ArcMenu ist für GNOME %s gebaut, hier läuft %s - wird trotzdem installiert, lädt womöglich nicht"
      M_ARCENABLE="ArcMenu installieren und auf das Zorin-OS-Layout umstellen"
      M_ARCNOENABLE="Die Erweiterung ließ sich nicht einschalten - unter Erweiterungen selbst aktivieren"
      M_DESKSET="Desktop: %s"
      M_DESKFOUND="Desktop gefunden: %s"
      M_NOSHELL="%s hat kein Panel-Thema zum Setzen - Fenster und Symbole sind fertig"
      M_DESKPANEL="%s hat kein Panel, das dieses Skript einrichten kann - die Fensterknöpfe sind trotzdem gesetzt"
      M_DESKNONE="%s: nur das Thema ist gesetzt - Panel und Fensterknöpfe bleiben, wie sie sind"
      M_BUTTONS_R="Fensterknöpfe rechts"
      M_BUTTONS_L="Fensterknöpfe links"
      M_NOAPPLY="Die Einstellungen von %s waren nicht erreichbar - das Thema ist installiert, wählen Sie es selbst"
      Q_DESKTOP="Welchen Desktop verwenden Sie?"
      Q_DESK1="Cinnamon    - Mints eigener, und eine Fedora-Variante"
      Q_DESK2="GNOME       - Fedoras Standard"
      Q_DESK3="Xfce        - leicht und klassisch"
      Q_DESK4="MATE        - der klassische GNOME-2-Desktop"
      Q_DESK5="KDE Plasma  - nur GTK-Programme; Plasmas eigenes Aussehen bleibt"
      Q_DESK6="Etwas anderes / unsicher - nur das Thema installieren"
      M_GSETFAIL="konnte %s %s nicht setzen"
      M_DISTROMISMATCH="Weiter als %s, obwohl der Rechner nach etwas anderem aussieht"
      ;;
  esac
}
set_messages en          # so the very first prompt already has its labels

# ---------- languages --------------------------------------------------------
# Locale, keyboard and timezone travel together, so one choice sets all three.
# The package names are only a starting point: pkg_install_available drops the
# ones that do not exist, and check-language-support fills in the rest, which is
# what makes this work for languages whose packages are not named to a pattern.
# XKB here is only the layout the language *suggests* - the keyboard is asked
# for separately below, because the two genuinely come apart: plenty of people
# want a Danish system on a US board, and nl and en_US share theirs outright.
lang_profile() {
  case "$1" in
    da)    LOCALE=da_DK.UTF-8; XKB=dk; ZONE=Europe/Copenhagen;  LSUP=da;    LANGLABEL="Dansk" ;;
    nb)    LOCALE=nb_NO.UTF-8; XKB=no; ZONE=Europe/Oslo;        LSUP=nb;    LANGLABEL="Norsk (bokmaal)" ;;
    nn)    LOCALE=nn_NO.UTF-8; XKB=no; ZONE=Europe/Oslo;        LSUP=nn;    LANGLABEL="Norsk (nynorsk)" ;;
    sv)    LOCALE=sv_SE.UTF-8; XKB=se; ZONE=Europe/Stockholm;   LSUP=sv;    LANGLABEL="Svenska" ;;
    fi)    LOCALE=fi_FI.UTF-8; XKB=fi; ZONE=Europe/Helsinki;    LSUP=fi;    LANGLABEL="Suomi" ;;
    is)    LOCALE=is_IS.UTF-8; XKB=is; ZONE=Atlantic/Reykjavik; LSUP=is;    LANGLABEL="Islenska" ;;
    de)    LOCALE=de_DE.UTF-8; XKB=de; ZONE=Europe/Berlin;      LSUP=de;    LANGLABEL="Deutsch" ;;
    # The Netherlands types on a US board in practice, whatever XKB offers.
    nl)    LOCALE=nl_NL.UTF-8; XKB=us; ZONE=Europe/Amsterdam;   LSUP=nl;    LANGLABEL="Nederlands" ;;
    en)    LOCALE=en_GB.UTF-8; XKB=gb; ZONE=Europe/London;      LSUP=en;    LANGLABEL="English (UK)" ;;
    en_us) LOCALE=en_US.UTF-8; XKB=us; ZONE=America/New_York;   LSUP=en;    LANGLABEL="English (US)" ;;
    fr)    LOCALE=fr_FR.UTF-8; XKB=fr; ZONE=Europe/Paris;       LSUP=fr;    LANGLABEL="Francais" ;;
    es)    LOCALE=es_ES.UTF-8; XKB=es; ZONE=Europe/Madrid;      LSUP=es;    LANGLABEL="Espanol" ;;
    it)    LOCALE=it_IT.UTF-8; XKB=it; ZONE=Europe/Rome;        LSUP=it;    LANGLABEL="Italiano" ;;
    pt)    LOCALE=pt_PT.UTF-8; XKB=pt; ZONE=Europe/Lisbon;      LSUP=pt;    LANGLABEL="Portugues" ;;
    pt_br) LOCALE=pt_BR.UTF-8; XKB=br; ZONE=America/Sao_Paulo;  LSUP=pt-br; LANGLABEL="Portugues (Brasil)" ;;
    pl)    LOCALE=pl_PL.UTF-8; XKB=pl; ZONE=Europe/Warsaw;      LSUP=pl;    LANGLABEL="Polski" ;;
    cs)    LOCALE=cs_CZ.UTF-8; XKB=cz; ZONE=Europe/Prague;      LSUP=cs;    LANGLABEL="Cestina" ;;
    sk)    LOCALE=sk_SK.UTF-8; XKB=sk; ZONE=Europe/Bratislava;  LSUP=sk;    LANGLABEL="Slovencina" ;;
    hu)    LOCALE=hu_HU.UTF-8; XKB=hu; ZONE=Europe/Budapest;    LSUP=hu;    LANGLABEL="Magyar" ;;
    ro)    LOCALE=ro_RO.UTF-8; XKB=ro; ZONE=Europe/Bucharest;   LSUP=ro;    LANGLABEL="Romana" ;;
    el)    LOCALE=el_GR.UTF-8; XKB=gr; ZONE=Europe/Athens;      LSUP=el;    LANGLABEL="Ellinika" ;;
    tr)    LOCALE=tr_TR.UTF-8; XKB=tr; ZONE=Europe/Istanbul;    LSUP=tr;    LANGLABEL="Turkce" ;;
    et)    LOCALE=et_EE.UTF-8; XKB=ee; ZONE=Europe/Tallinn;     LSUP=et;    LANGLABEL="Eesti" ;;
    lv)    LOCALE=lv_LV.UTF-8; XKB=lv; ZONE=Europe/Riga;        LSUP=lv;    LANGLABEL="Latviesu" ;;
    lt)    LOCALE=lt_LT.UTF-8; XKB=lt; ZONE=Europe/Vilnius;     LSUP=lt;    LANGLABEL="Lietuviu" ;;
    uk)    LOCALE=uk_UA.UTF-8; XKB=ua; ZONE=Europe/Kyiv;        LSUP=uk;    LANGLABEL="Ukrainska" ;;
    *)  return 1 ;;
  esac
  return 0
}
LANGS_ALL="da nb nn sv fi is de nl en en_us fr es it pt pt_br pl cs sk hu ro el tr et lv lt uk"

case " $LANGS_ALL " in
  *" ${LANG_CHOICE:-da} "*) ;;
  *) die "--lang must be one of: $LANGS_ALL" ;;
esac

# ---------- what do you want it to look like? --------------------------------
have_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

# A small Zorin-style picker. The prompt goes to the terminal rather than
# stdout so the caller can capture just the answer - and it reads /dev/tty
# because stdin is the script itself when this arrives through curl | bash.
menu() {
  local title="$1" def="$2"; shift 2
  local n=$# i=1 opt ans
  { printf '\n%s==>%s %s%s%s\n' "$C_B" "$C_0" "$C_B" "$title" "$C_0"
    for opt in "$@"; do
      if [ "$i" = "$def" ]; then printf '   %d) %s  %s%s%s\n' "$i" "$opt" "$C_G" "$M_DEFAULT" "$C_0"
      else                        printf '   %d) %s\n' "$i" "$opt"; fi
      i=$((i + 1))
    done
    fmt "   $M_CHOICE" "$def"
  } > /dev/tty
  read -r ans < /dev/tty || ans=''
  case "$ans" in ''|*[!0-9]*) ans="$def" ;; esac
  if [ "$ans" -lt 1 ] || [ "$ans" -gt "$n" ]; then ans="$def"; fi
  printf '%s' "$ans"
}

# Same idea as menu(), for an answer that is not one of a list.
prompt_line() {                    # prompt_line PROMPT -> answer on stdout
  local ans
  { printf '\n   %s' "$1"; } > /dev/tty
  read -r ans < /dev/tty || ans=''
  printf '%s' "$ans"
}

INTERACTIVE=0
if [ "$ASSUME_YES" = 0 ] && have_tty; then INTERACTIVE=1; fi

# ---------- which distribution is this? --------------------------------------
# This one comes before everything else, language included: it decides which
# package manager runs, what the packages are called, and how the locale and
# the keyboard are set. Everything after it depends on the answer.
#
# os-release is read in a subshell on purpose. It defines VERSION and VARIANT,
# and this script has variables by those names.
detect_distro() {
  local id like
  id="$(. /etc/os-release 2>/dev/null || true; printf '%s' "${ID:-}")"
  like="$(. /etc/os-release 2>/dev/null || true; printf '%s' "${ID_LIKE:-}")"
  # Ubuntu and Mint both say ID_LIKE=debian, so they have to be caught first;
  # what is left saying debian really is Debian, and names its packages its
  # own way - no language-pack-*, and Firefox is the ESR build.
  # The exact ID first, so a derivative is not mistaken for its parent.
  case "$id" in
    linuxmint|linuxmint-*)                     printf 'mint';   return 0 ;;
    ubuntu|pop|elementary|zorin|neon|tuxedo)   printf 'ubuntu'; return 0 ;;
    debian|devuan|raspbian)                    printf 'debian'; return 0 ;;
    fedora|nobara|rhel|centos|almalinux|rocky) printf 'fedora'; return 0 ;;
    arch|manjaro|endeavouros|garuda|cachyos|artix) printf 'arch'; return 0 ;;
  esac
  # Then whatever family it says it belongs to.
  case " $like " in
    *linuxmint*)     printf 'mint';   return 0 ;;
    *ubuntu*)        printf 'ubuntu'; return 0 ;;
    *debian*)        printf 'debian'; return 0 ;;
    *fedora*|*rhel*) printf 'fedora'; return 0 ;;
    *arch*)          printf 'arch';   return 0 ;;
  esac
  # No usable ID: go by which package manager is actually installed.
  if command -v apt-get >/dev/null 2>&1; then printf 'debian'; return 0; fi
  if command -v dnf     >/dev/null 2>&1; then printf 'fedora'; return 0; fi
  if command -v pacman  >/dev/null 2>&1; then printf 'arch';   return 0; fi
  printf ''
  return 0
}

# The package manager and the name to print, kept in one place.
distro_profile() {
  case "$1" in
    debian) PKG=apt;    DISTROLABEL="Debian" ;;
    ubuntu) PKG=apt;    DISTROLABEL="Ubuntu" ;;
    mint)   PKG=apt;    DISTROLABEL="Linux Mint" ;;
    fedora) PKG=dnf;    DISTROLABEL="Fedora" ;;
    arch)   PKG=pacman; DISTROLABEL="Arch Linux" ;;
    *) return 1 ;;
  esac
  return 0
}

DETECTED_DISTRO="$(detect_distro)"
if [ -z "$DISTRO" ]; then
  if [ "$INTERACTIVE" = 1 ]; then
    # Asked before the catalogue is loaded, so the wording has to work in
    # every language the script speaks. Distribution names do.
    case "$DETECTED_DISTRO" in
      debian) DISTRO_DEFAULT=1 ;; ubuntu) DISTRO_DEFAULT=2 ;; mint) DISTRO_DEFAULT=3 ;;
      fedora) DISTRO_DEFAULT=4 ;; arch)   DISTRO_DEFAULT=5 ;; *) DISTRO_DEFAULT=3 ;;
    esac
    case "$(menu "Distribution" "$DISTRO_DEFAULT" \
        "Debian" \
        "Ubuntu      / Pop!_OS / elementary / Zorin" \
        "Linux Mint" \
        "Fedora      / Nobara / RHEL / Alma / Rocky" \
        "Arch Linux  / Manjaro / EndeavourOS / CachyOS")" in
      1) DISTRO=debian ;; 2) DISTRO=ubuntu ;; 3) DISTRO=mint ;;
      4) DISTRO=fedora ;; 5) DISTRO=arch ;;
    esac
  else
    DISTRO="${DETECTED_DISTRO:-mint}"
  fi
fi
distro_profile "$DISTRO" || die "unknown distribution: $DISTRO"

if [ "$DO_LANG" = 1 ] && [ -z "$LANG_CHOICE" ]; then
  if [ "$INTERACTIVE" = 1 ]; then
    # Asked before any catalogue is loaded, so it names itself in both
    # languages and lists each option in its own tongue - a language you can
    # read is the one thing you cannot be asked about in a language you cannot.
    # Twenty-six of them in one list is a wall, so the common ones come first
    # and the rest are one keystroke behind them.
    case "$(menu "Sprog / Language" 1 \
        "Dansk" "Norsk (bokmål)" "Svenska" "Suomi" "Íslenska" "Deutsch" \
        "Nederlands" "English (UK)" "English (US)" "Français" "Español" "Italiano" \
        "Flere sprog / More languages ...")" in
      1) LANG_CHOICE=da ;;  2) LANG_CHOICE=nb ;;  3) LANG_CHOICE=sv ;;
      4) LANG_CHOICE=fi ;;  5) LANG_CHOICE=is ;;  6) LANG_CHOICE=de ;;
      7) LANG_CHOICE=nl ;;  8) LANG_CHOICE=en ;;  9) LANG_CHOICE=en_us ;;
     10) LANG_CHOICE=fr ;; 11) LANG_CHOICE=es ;; 12) LANG_CHOICE=it ;;
     13) case "$(menu "Flere sprog / More languages" 1 \
             "Norsk (nynorsk)" "Português" "Português (Brasil)" "Polski" \
             "Čeština" "Slovenčina" "Magyar" "Română" "Ελληνικά" "Türkçe" \
             "Eesti" "Latviešu" "Lietuvių" "Українська")" in
           1) LANG_CHOICE=nn ;;  2) LANG_CHOICE=pt ;;  3) LANG_CHOICE=pt_br ;;
           4) LANG_CHOICE=pl ;;  5) LANG_CHOICE=cs ;;  6) LANG_CHOICE=sk ;;
           7) LANG_CHOICE=hu ;;  8) LANG_CHOICE=ro ;;  9) LANG_CHOICE=el ;;
          10) LANG_CHOICE=tr ;; 11) LANG_CHOICE=et ;; 12) LANG_CHOICE=lv ;;
          13) LANG_CHOICE=lt ;; 14) LANG_CHOICE=uk ;;
         esac ;;
    esac
  else
    LANG_CHOICE=da
  fi
fi
[ -n "$LANG_CHOICE" ] || LANG_CHOICE=da
lang_profile "$LANG_CHOICE" || die "unknown language: $LANG_CHOICE"
# From here on the script speaks the language you picked.
set_messages "${UI_LANG:-$LANG_CHOICE}"
# Explicit flags win over whatever the language would have picked.
[ -n "$KEYBOARD" ] && XKB="$KEYBOARD"
[ -n "$TIMEZONE" ] && ZONE="$TIMEZONE"

# ---------- and which keyboard? ----------------------------------------------
# Its own question, not a consequence of the language. The language's layout is
# only the default, because wanting a Danish system on the board you already
# own is completely ordinary - and this is the first question the script can
# ask in the language you just chose.
kb_known() {                       # is this a layout X actually has?
  command -v localectl >/dev/null 2>&1 || return 0   # cannot check, so accept
  localectl list-x11-keymap-layouts 2>/dev/null | grep -qx -- "$1"
}

if [ "$DO_LANG" = 1 ] && [ -z "$KEYBOARD" ] && [ "$INTERACTIVE" = 1 ]; then
  case "$(menu "$Q_KB" 1 \
      "$(fmt "$Q_KB1" "$LANGLABEL" "$XKB")" \
      "English (US)      - us" "English (UK)      - gb" "Deutsch           - de" \
      "Dansk             - dk" "Norsk             - no" "Svenska           - se" \
      "Suomi             - fi" "Français          - fr" "Español           - es" \
      "Italiano          - it" "$Q_KBOTHER")" in
    2) XKB=us ;;  3) XKB=gb ;;  4) XKB=de ;;  5) XKB=dk ;;  6) XKB=no ;;
    7) XKB=se ;;  8) XKB=fi ;;  9) XKB=fr ;; 10) XKB=es ;; 11) XKB=it ;;
    12) ans="$(prompt_line "$M_KBASK")"
        # Take the code only if the system admits to having it; a typo here
        # is a keyboard you cannot type your own password on.
        if [ -n "$ans" ] && kb_known "$ans"; then XKB="$ans"
        elif [ -n "$ans" ]; then warn "$(fmt "$M_KBUNKNOWN" "$ans" "$XKB")"; fi ;;
  esac
fi
if [ -n "$KB_VARIANT" ]; then XKB_FULL="$XKB+$KB_VARIANT"; else XKB_FULL="$XKB"; fi

# ---------- and which timezone? ----------------------------------------------
# Its own question too. The language only guesses - a Danish system on a machine
# standing in Berlin is nothing unusual - and a clock an hour out is the first
# thing you notice. The list is the zones this script's languages live in; the
# world has several hundred more, so the last entry takes any of them.
tz_known() {                       # is this a zone the system actually has?
  case "$1" in
    ""|/*|*..*|*[!A-Za-z0-9/_+-]*) return 1 ;;
  esac
  if command -v timedatectl >/dev/null 2>&1; then
    if timedatectl list-timezones 2>/dev/null | grep -qx -- "$1"; then
      return 0
    fi
  fi
  [ -f "/usr/share/zoneinfo/$1" ]
}

# --timezone skips the question, so it is checked here instead: a zone the
# machine does not have would only fail further down, after the locale is set.
if [ "$DO_LANG" = 1 ] && [ -n "$TIMEZONE" ] && ! tz_known "$TIMEZONE"; then
  die "unknown timezone: $TIMEZONE"
fi

if [ "$DO_LANG" = 1 ] && [ -z "$TIMEZONE" ] && [ "$INTERACTIVE" = 1 ]; then
  case "$(menu "$Q_TZ" 1 \
      "$(fmt "$Q_TZ1" "$LANGLABEL" "$ZONE")" \
      "Europe/Copenhagen   - Danmark" \
      "Europe/Oslo         - Norge" \
      "Europe/Stockholm    - Sverige" \
      "Europe/Helsinki     - Suomi" \
      "Atlantic/Reykjavik  - Ísland" \
      "Europe/Berlin       - Deutschland, Nederland" \
      "Europe/London       - United Kingdom, Ireland" \
      "America/New_York    - USA (East)" \
      "UTC                 - UTC" \
      "$Q_TZOTHER")" in
    2) ZONE=Europe/Copenhagen ;;   3) ZONE=Europe/Oslo ;;
    4) ZONE=Europe/Stockholm ;;    5) ZONE=Europe/Helsinki ;;
    6) ZONE=Atlantic/Reykjavik ;;  7) ZONE=Europe/Berlin ;;
    8) ZONE=Europe/London ;;       9) ZONE=America/New_York ;;
   10) ZONE=UTC ;;
   11) ans="$(prompt_line "$M_TZASK")"
       # A name the machine has never heard of would leave the clock where it
       # is, so it is only taken when the zone is really on disk.
       if [ -n "$ans" ] && tz_known "$ans"; then ZONE="$ans"
       elif [ -n "$ans" ]; then warn "$(fmt "$M_TZUNKNOWN" "$ans" "$ZONE")"; fi ;;
  esac
fi

# ---------- preflight ---------------------------------------------------------
step "$S_PREFLIGHT"
[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root. The script calls sudo where it needs to."
command -v sudo >/dev/null || die "sudo not found"
case "$PKG" in
  dnf)    command -v dnf >/dev/null \
            || die "No dnf here - is this really Fedora? Try --distro debian" ;;
  pacman) command -v pacman >/dev/null \
            || die "No pacman here - is this really Arch? Try --distro debian" ;;
  *)      command -v apt-get >/dev/null \
            || die "No apt-get here - is this really Mint/Ubuntu/Debian? Try --distro fedora" ;;
esac
PRETTY="$(. /etc/os-release 2>/dev/null || true; printf '%s' "${PRETTY_NAME:-unknown}")"
note "$(fmt "$M_DETECTED" "$PRETTY")"
if [ -n "$DETECTED_DISTRO" ] && [ "$DETECTED_DISTRO" != "$DISTRO" ]; then
  warn "$(fmt "$M_DISTROMISMATCH" "$DISTROLABEL")"
fi
if [ "$DRY_RUN" = 0 ]; then
  sudo -v || die "sudo authentication failed"
  # keep the sudo ticket warm for the length of the run
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT
fi
# A live USB session throws all of this away at reboot. Say so before spending
# ten minutes on it.
if [ -d /rofs ] || [ -e /etc/casper.conf ] || [ -d /run/initramfs/live ] \
   || grep -qs -e 'boot=casper' -e 'rd.live.image' /proc/cmdline; then
  warn "$M_LIVE1"
  warn "$M_LIVE2"
  echo
fi
ok "$M_PREOK"

APT="sudo env DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Use-Pty=0"
DNF="sudo dnf -y"
# --needed so a second run is a no-op, and no -Sy: refreshing the database
# without upgrading is the one thing that genuinely breaks an Arch system.
PACMAN="sudo pacman -S --needed --noconfirm"

# Does the archive know this package? The two package managers answer the same
# question in their own words, and neither may print anything while doing it.
pkg_known() {
  case "$PKG" in
    dnf)    dnf -q info "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
    *)      apt-cache show "$1" >/dev/null 2>&1 ;;
  esac
}

# Refresh the package lists. Not fatal either way: the live session carries a
# cdrom: source that always fails, and a stale mirror should not cost you the
# whole run.
pkg_refresh() {
  case "$PKG" in
    dnf)    runq sudo dnf -q makecache --refresh || warn "$M_PKGUPD" ;;
    # Deliberately nothing: pacman -Sy on its own leaves the machine half
    # upgraded, and -Syu is a decision this script has no business making.
    pacman) note "$M_PACSYNC" ;;
    *)      runq sudo apt-get update -qq        || warn "$M_PKGUPD" ;;
  esac
}

# Install packages, skipping any the archive does not have. Names drift from
# release to release, and between Mint and Fedora they differ outright - so
# the caller may hand over a list that is only half-right for this machine.
pkg_install_available() {
  local want=() missing=() p
  for p in "$@"; do
    if pkg_known "$p"; then want+=("$p"); else missing+=("$p"); fi
  done
  [ ${#missing[@]} -eq 0 ] || note "$(fmt "$M_SKIPPED" "${missing[*]}")"
  [ ${#want[@]} -gt 0 ] || return 0
  case "$PKG" in
    dnf)    runq $DNF install "${want[@]}" ;;
    pacman) runq $PACMAN "${want[@]}" ;;
    *)      runq $APT install "${want[@]}" ;;
  esac && ok "$(fmt "$M_INSTALLED" "${want[*]}")" \
       || warn "$(fmt "$M_PKGFAIL" "${want[*]}")"
}

# Never returns non-zero: a missing key on some Cinnamon version must not take
# the whole run down through `set -e`.
gset() {
  [ "$DRY_RUN" = 1 ] && { printf '  %s[dry]%s gsettings set %s\n' "$C_Y" "$C_0" "$*"; return 0; }
  gsettings set "$@" 2>/dev/null || warn "$(fmt "$M_GSETFAIL" "$1" "$2")"
  return 0
}

# ---------- which desktop is this? -------------------------------------------
# A theme is just files on disk; what differs is who you tell about it, and
# every desktop keeps that somewhere else. Guess it from the session first,
# then from what is running, and only then from what happens to be installed -
# in that order, because the first one is the only one that can be certain.
detect_desktop() {
  local d p schemas
  d="$(printf '%s %s' "${XDG_CURRENT_DESKTOP:-}" "${DESKTOP_SESSION:-}" \
       | tr '[:upper:]' '[:lower:]')"
  case "$d" in
    *cinnamon*)      printf 'cinnamon'; return 0 ;;
    *xfce*)          printf 'xfce';     return 0 ;;
    *mate*)          printf 'mate';     return 0 ;;
    *kde*|*plasma*)  printf 'plasma';   return 0 ;;
    *gnome*|*unity*) printf 'gnome';    return 0 ;;
  esac
  for p in cinnamon xfce4-session mate-session plasmashell gnome-shell; do
    if pgrep -x "$p" >/dev/null 2>&1; then
      case "$p" in
        cinnamon)      printf 'cinnamon' ;;
        xfce4-session) printf 'xfce' ;;
        mate-session)  printf 'mate' ;;
        plasmashell)   printf 'plasma' ;;
        gnome-shell)   printf 'gnome' ;;
      esac
      return 0
    fi
  done
  # Nothing running - over SSH, say. Fall back to what is installed, so the
  # suggestion is at least a desktop this machine actually has.
  if command -v gsettings >/dev/null 2>&1; then
    schemas="$(gsettings list-schemas 2>/dev/null || true)"
    case "$schemas" in *org.cinnamon.desktop.interface*) printf 'cinnamon'; return 0 ;; esac
    case "$schemas" in *org.mate.interface*)             printf 'mate';     return 0 ;; esac
  fi
  if command -v xfconf-query >/dev/null 2>&1; then printf 'xfce'; return 0; fi
  printf ''
  return 0
}

# What to call it, and where to look afterwards to see that it took.
desktop_profile() {
  case "$1" in
    cinnamon) DESKLABEL="Cinnamon"
              CHECK_CMD="gsettings get org.cinnamon.desktop.interface gtk-theme" ;;
    gnome)    DESKLABEL="GNOME"
              CHECK_CMD="gsettings get org.gnome.desktop.interface gtk-theme" ;;
    xfce)     DESKLABEL="Xfce"
              CHECK_CMD="xfconf-query -c xsettings -p /Net/ThemeName" ;;
    mate)     DESKLABEL="MATE"
              CHECK_CMD="gsettings get org.mate.interface gtk-theme" ;;
    plasma)   DESKLABEL="KDE Plasma"
              CHECK_CMD="grep gtk-theme-name ~/.config/gtk-3.0/settings.ini" ;;
    other)    DESKLABEL="GTK"
              CHECK_CMD="grep gtk-theme-name ~/.config/gtk-3.0/settings.ini" ;;
    *) return 1 ;;
  esac
  return 0
}

# ---------- writing a setting to whichever desktop that is -------------------
# Cinnamon, GNOME and MATE all keep these in gsettings, under three schema
# names of their own. Xfce keeps them in xfconf. Plasma and anything else read
# GTK's own settings.ini - which every GTK app falls back to when no settings
# daemon is answering, so it is written on all of them as a backstop.
xfset() {                          # xfset CHANNEL PROPERTY TYPE VALUE
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s xfconf-query -c %s -p %s -s %s\n' "$C_Y" "$C_0" "$1" "$2" "$4"; return 0
  fi
  xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" >/dev/null 2>&1 \
    || warn "$(fmt "$M_GSETFAIL" "$1" "$2")"
  return 0
}

# GTK's ini has one [Settings] section and nothing else in practice, so a key
# that is not already there can simply go at the end.
gtkini_set() {                     # gtkini_set KEY VALUE
  local f
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s %s=%s in ~/.config/gtk-{3,4}.0/settings.ini\n' "$C_Y" "$C_0" "$1" "$2"; return 0
  fi
  for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    mkdir -p "${f%/*}"
    [ -f "$f" ] || printf '[Settings]\n' > "$f"
    grep -q '^\[Settings\]' "$f" || printf '[Settings]\n' >> "$f"
    if grep -q "^$1=" "$f"; then sed -i "s|^$1=.*|$1=$2|" "$f"
    else                         printf '%s=%s\n' "$1" "$2" >> "$f"; fi
  done
  return 0
}

set_gtk_theme() {
  case "$DESKTOP" in
    cinnamon) gset org.cinnamon.desktop.interface gtk-theme "$1" ;;
    gnome)    gset org.gnome.desktop.interface    gtk-theme "$1" ;;
    mate)     gset org.mate.interface             gtk-theme "$1" ;;
    xfce)     xfset xsettings /Net/ThemeName string "$1" ;;
  esac
  gtkini_set gtk-theme-name "$1"
}

set_icon_theme() {
  case "$DESKTOP" in
    cinnamon) gset org.cinnamon.desktop.interface icon-theme "$1" ;;
    gnome)    gset org.gnome.desktop.interface    icon-theme "$1" ;;
    mate)     gset org.mate.interface             icon-theme "$1" ;;
    xfce)     xfset xsettings /Net/IconThemeName string "$1" ;;
  esac
  gtkini_set gtk-icon-theme-name "$1"
}

# The titlebars, which are drawn by the window manager rather than by GTK.
set_wm_theme() {
  case "$DESKTOP" in
    cinnamon) gset org.cinnamon.desktop.wm.preferences theme "$1" ;;
    gnome)    gset org.gnome.desktop.wm.preferences    theme "$1" ;;
    mate)     gset org.mate.Marco.general              theme "$1" ;;
    xfce)     xfset xfwm4 /general/theme string "$1" ;;
  esac
}

# Which side the buttons sit on. Metacity, Mutter and Marco share a syntax;
# xfwm4 has one of its own, where the letters are the buttons and the bar
# splits left from right.
set_button_layout() {              # set_button_layout right|left
  local gtkish xfwmish
  if [ "$1" = left ]; then gtkish="close,minimize,maximize:"; xfwmish="CHM|O"
  else                     gtkish=":minimize,maximize,close"; xfwmish="O|HMC"; fi
  case "$DESKTOP" in
    cinnamon) gset org.cinnamon.desktop.wm.preferences button-layout "$gtkish" ;;
    gnome)    gset org.gnome.desktop.wm.preferences    button-layout "$gtkish" ;;
    mate)     gset org.mate.Marco.general              button-layout "$gtkish" ;;
    xfce)     xfset xfwm4 /general/button_layout string "$xfwmish" ;;
  esac
}

# Only the two desktops whose clock this script also owns the panel of.
set_clock_24h() {
  case "$DESKTOP" in
    cinnamon) gset org.cinnamon.desktop.interface clock-use-24h true ;;
    gnome)    gset org.gnome.desktop.interface    clock-format  24h ;;
  esac
}

# Is there anything to write to at all?
desktop_reachable() {
  case "$DESKTOP" in
    xfce)         command -v xfconf-query >/dev/null 2>&1 ;;
    plasma|other) return 0 ;;
    *)            command -v gsettings >/dev/null 2>&1 ;;
  esac
}


# ---------- the rest of the questions ---------------------------------------
# Which desktop, before anything about how it should look: the answer decides
# where every setting below is written, and what can be set at all.
DETECTED_DESKTOP="$(detect_desktop)"
if [ -z "$DESKTOP" ]; then
  # No luck detecting it? Suggest the one the chosen distribution ships with.
  SUGGEST="$DETECTED_DESKTOP"
  if [ -z "$SUGGEST" ]; then
    case "$DISTRO" in fedora|debian|arch) SUGGEST=gnome ;; *) SUGGEST=cinnamon ;; esac
  fi
  if [ "$INTERACTIVE" = 1 ]; then
    case "$SUGGEST" in
      cinnamon) DESK_DEFAULT=1 ;; gnome) DESK_DEFAULT=2 ;; xfce)   DESK_DEFAULT=3 ;;
      mate)     DESK_DEFAULT=4 ;; plasma) DESK_DEFAULT=5 ;; *)     DESK_DEFAULT=6 ;;
    esac
    [ -n "$DETECTED_DESKTOP" ] && note "$(fmt "$M_DESKFOUND" "$DETECTED_DESKTOP")"
    case "$(menu "$Q_DESKTOP" "$DESK_DEFAULT" \
        "$Q_DESK1" "$Q_DESK2" "$Q_DESK3" "$Q_DESK4" "$Q_DESK5" "$Q_DESK6")" in
      1) DESKTOP=cinnamon ;; 2) DESKTOP=gnome ;;  3) DESKTOP=xfce ;;
      4) DESKTOP=mate ;;     5) DESKTOP=plasma ;; 6) DESKTOP=other ;;
    esac
  else
    DESKTOP="$SUGGEST"
  fi
fi
desktop_profile "$DESKTOP" || die "unknown desktop: $DESKTOP"
note "$(fmt "$M_DESKSET" "$DESKLABEL")"

if [ "$DO_THEME" = 1 ]; then
  if [ -z "$STYLE" ]; then
    if [ "$INTERACTIVE" = 1 ]; then
      case "$(menu "$Q_LOOK" 1 \
          "$Q_LOOK1" "$Q_LOOK2" "$Q_LOOK3" "$Q_LOOK4" "$Q_LOOK5" \
          "$Q_LOOK6" "$Q_LOOK7" "$Q_LOOK8" "$Q_LOOK9" "$Q_LOOK10")" in
        1) STYLE=win11 ;;    2) STYLE=win10 ;;  3) STYLE=mac ;;
        4) STYLE=arc ;;      5) STYLE=orchis ;; 6) STYLE=colloid ;;
        7) STYLE=graphite ;; 8) STYLE=nordic ;; 9) STYLE=mint ;; 10) STYLE=none ;;
      esac
    else
      STYLE=win11
    fi
  fi

  # Windows-10-temaet findes kun i én udgave, så det spørgsmål springes over.
  if [ -z "$VARIANT" ]; then
    if [ "$STYLE" = win10 ] || [ "$STYLE" = none ]; then
      VARIANT=light
    elif [ "$INTERACTIVE" = 1 ]; then
      case "$(menu "$Q_LIGHT" 1 "$Q_LIGHT1" "$Q_LIGHT2")" in
        1) VARIANT=light ;; 2) VARIANT=dark ;;
      esac
    else
      VARIANT=light
    fi
  fi
fi

if [ -z "$LAYOUT" ]; then
  # Picking the macOS look and then getting a Windows taskbar would be odd, so
  # the default follows the theme you chose.
  case "${STYLE:-}" in
    win11) LAYOUT_DEFAULT=2 ;;
    mac)   LAYOUT_DEFAULT=3 ;;
    *)     LAYOUT_DEFAULT=1 ;;
  esac
  if [ "$INTERACTIVE" = 1 ]; then
    case "$(menu "$Q_LAYOUT" "$LAYOUT_DEFAULT" \
        "$Q_LAYOUT1" "$Q_LAYOUT2" "$Q_LAYOUT3" "$Q_LAYOUT4")" in
      1) LAYOUT=traditional ;; 2) LAYOUT=win11 ;; 3) LAYOUT=mac ;; 4) LAYOUT=mint ;;
    esac
  else
    case "$LAYOUT_DEFAULT" in
      2) LAYOUT=win11 ;; 3) LAYOUT=mac ;; *) LAYOUT=traditional ;;
    esac
  fi
fi

if [ -z "$MENU" ]; then
  # A Windows 11-ish panel is asking for a start menu; anything else is not,
  # so the default only offers to replace the menu when it fits what you just
  # picked - and then only with the one this desktop can actually take.
  MENU_DEFAULT=1
  if [ "$LAYOUT" = win11 ]; then
    case "$DESKTOP" in cinnamon) MENU_DEFAULT=3 ;; gnome) MENU_DEFAULT=2 ;; esac
  fi
  if [ "$INTERACTIVE" = 1 ]; then
    case "$(menu "$Q_MENU" "$MENU_DEFAULT" "$Q_MENU1" "$Q_MENU2" "$Q_MENU3")" in
      1) MENU=system ;; 2) MENU=zorin ;; 3) MENU=cinnamenu ;;
    esac
  else
    case "$MENU_DEFAULT" in 2) MENU=zorin ;; 3) MENU=cinnamenu ;; *) MENU=system ;; esac
  fi
fi

# /etc/locale.gen is where Debian and Arch decide which locales exist at all,
# and neither builds one that is not listed there. Ubuntu and Mint read the same
# file, so uncommenting the line and running locale-gen with no arguments is the
# one road that works on every apt and pacman system.
enable_locale() {
  local line="$LOCALE UTF-8"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s ' "$C_Y" "$C_0"; fmt "$M_LOCALEGEN\n" "$line"
    return 0
  fi
  if [ -f /etc/locale.gen ] && grep -qs "^[#[:space:]]*$LOCALE UTF-8" /etc/locale.gen; then
    sudo sed -i "s/^[#[:space:]]*\($LOCALE UTF-8\)/\1/" /etc/locale.gen
  else
    printf '%s\n' "$line" | sudo tee -a /etc/locale.gen >/dev/null
  fi
  sudo locale-gen >/dev/null 2>&1 || warn "$(fmt "$M_LOCALEGENFAIL" "$LOCALE")"
}

# systemd checks every value handed to `localectl set-locale` against its idea
# of a locale name, and a locale name may not contain a colon. LANGUAGE is a
# colon-separated list by definition, so localectl refuses it out of hand -
# "Locale da_DK:da:en_US:en is not valid, refusing" - whatever the list says.
# The same line read back out of /etc/locale.conf is accepted without a word,
# so write it there ourselves. It has to happen after localectl has run:
# set-locale rewrites the whole file and would throw the line away again.
write_language() {
  local f=/etc/locale.conf
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s ' "$C_Y" "$C_0"; fmt "$M_LANGWRITE\n" "$FALLBACK" "$f"
    return 0
  fi
  if [ -f "$f" ]; then
    sudo sed -i '/^[[:space:]]*LANGUAGE=/d' "$f"
  fi
  printf 'LANGUAGE=%s\n' "$FALLBACK" | sudo tee -a "$f" >/dev/null
}

# ---------- everything you picked, before a single thing is changed ----------
# Seven questions is enough that you can lose track of what you answered, and
# every one of them is easier to correct here than afterwards. Nothing above
# this line has written anything.
SUMMARY_FILE="$HOME/.local/share/kasper-linux/last-run.txt"
# printf pads %-16s by bytes, so a label with an ae, oe or aa in it would come
# out short. Pad by characters instead, and the translations can be spelled the
# way they are actually spelled.
srow() {                           # srow LABEL VALUE
  local n=$(( 16 - ${#1} ))
  [ "$n" -lt 1 ] && n=1
  printf '   %s%*s%s\n' "$1" "$n" '' "$2"
}
summary_lines() {
  srow "$L_DISTRO"  "$DISTROLABEL"
  srow "$L_DESKTOP" "$DESKLABEL"
  if [ "$DO_LANG" = 1 ]; then
    srow "$L_LANG" "$LANGLABEL ($LOCALE)"
    srow "$L_KB"   "$XKB_FULL"
    srow "$L_TZ"   "$ZONE"
  fi
  if [ "$DO_THEME" = 1 ] && [ "$STYLE" != none ]; then
    srow "$L_THEME" "$STYLE ($VARIANT)"
  fi
  srow "$L_LAYOUT" "$LAYOUT"
  srow "$L_MENU"   "$MENU"
}

if [ "$INTERACTIVE" = 1 ]; then
  step "$S_SUMMARY"
  summary_lines
  case "$(menu "$Q_GO" 1 "$Q_GO1" "$Q_GO2")" in
    2) note "$M_ABORT"; exit 0 ;;
  esac
fi

# ---------- language layer ----------------------------------------------------
# Locale, timezone and keyboard. The timezone is the only one of the three that
# is set the same way on both families; the other two are not close.
if [ "$DO_LANG" = 1 ]; then
  step "$(fmt "$S_LANG" "$LANGLABEL")"

  # LANGUAGE keeps English as the fallback throughout, so anything not
  # translated yet stays readable instead of dropping to the C locale. The list
  # is built from the locale itself - da_DK.UTF-8 gives da_DK:da - and every
  # entry goes in once, so English asks for en_US:en instead of asking for the
  # same two things twice.
  LOCALE_OK=1
  FALLBACK=""
  for fb in "${LOCALE%%.*}" "${LOCALE%%_*}" en_US en; do
    case ":$FALLBACK:" in *":$fb:"*) continue ;; esac
    FALLBACK="${FALLBACK:+$FALLBACK:}$fb"
  done
  case "$PKG" in
    dnf)
      # Fedora ships each locale in its own glibc-langpack, and localectl will
      # not take a locale that is not on disk yet - so install first, set after.
      pkg_install_available "glibc-langpack-$LSUP"
      run sudo localectl set-locale "LANG=$LOCALE" \
        || { warn "$(fmt "$M_LOCALEFAIL" "$LOCALE")"; LOCALE_OK=0; }
      write_language
      ;;
    pacman)
      # Arch builds nothing by default: the locale is generated here and then
      # written to /etc/locale.conf, which is what localectl edits.
      enable_locale
      run sudo localectl set-locale "LANG=$LOCALE" \
        || { warn "$(fmt "$M_LOCALEFAIL" "$LOCALE")"; LOCALE_OK=0; }
      write_language
      ;;
    *)
      # Debian keeps locale-gen in its own package, and it may not be there yet.
      if ! command -v locale-gen >/dev/null 2>&1; then
        pkg_refresh
        pkg_install_available locales
      fi
      enable_locale
      run sudo update-locale "LANG=$LOCALE" \
          "LANGUAGE=$FALLBACK" "LC_MESSAGES=$LOCALE" \
        || { warn "$(fmt "$M_LOCALEFAIL" "$LOCALE")"; LOCALE_OK=0; }
      ;;
  esac
  if [ "$LOCALE_OK" = 1 ]; then ok "$(fmt "$M_LOCALE" "$LOCALE")"; fi

  if run sudo timedatectl set-timezone "$ZONE"; then
    ok "$(fmt "$M_TZ" "$ZONE")"
  else
    warn "$(fmt "$M_TZFAIL" "$ZONE")"
  fi

  if [ "$PKG" != apt ]; then
    # On Fedora and Arch localectl is the supported road, and it writes both
    # keymaps - the console one and the X11 one.
    run sudo localectl set-keymap "$XKB" || warn "$M_KBFAIL"
    if [ -n "$KB_VARIANT" ]; then
      run sudo localectl set-x11-keymap "$XKB" "" "$KB_VARIANT" || warn "$M_KBFAIL"
    else
      run sudo localectl set-x11-keymap "$XKB" || warn "$M_KBFAIL"
    fi
  else
    # Here `localectl set-x11-keymap` is a dead end: Mint inherits Debian's
    # systemd patch that answers "not supported in Debian". The Debian way is
    # to write /etc/default/keyboard and let the console tools reload it.
    if [ "$DRY_RUN" = 1 ]; then
      printf '  %s[dry]%s ' "$C_Y" "$C_0"; fmt "$M_KBWRITE\n" "$XKB"
    else
      sudo tee /etc/default/keyboard >/dev/null <<KBEOF
# Written by kasper.sh/linux
XKBMODEL="pc105"
XKBLAYOUT="$XKB"
XKBVARIANT="$KB_VARIANT"
XKBOPTIONS=""
BACKSPACE="guess"
KBEOF
    fi
    runq sudo dpkg-reconfigure -f noninteractive keyboard-configuration \
      || warn "$M_KBFAIL"
    command -v setupcon >/dev/null 2>&1 && { runq sudo setupcon --save || true; }
  fi
  # Apply it to the running X session and to the desktop's own list of
  # layouts too - otherwise the setting is only true after the next reboot.
  if [ -n "${DISPLAY:-}" ] && command -v setxkbmap >/dev/null 2>&1; then
    if [ -n "$KB_VARIANT" ]; then runq setxkbmap -layout "$XKB" -variant "$KB_VARIANT" || true
    else                          runq setxkbmap "$XKB" || true; fi
  fi
  if command -v gsettings >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    gset org.gnome.desktop.input-sources sources "[('xkb','$XKB_FULL')]"
  fi
  ok "$(fmt "$M_KB" "$XKB_FULL")"

  step "$(fmt "$S_PACKS" "$LANGLABEL")"
  pkg_refresh
  case "$DISTRO" in
    fedora)
      # langpacks-XX is the metapackage that drags in the rest; the others are
      # named to a pattern of their own on this side.
      pkg_install_available \
        "langpacks-$LSUP" "glibc-langpack-$LSUP" \
        "hunspell-$LSUP" "hyphen-$LSUP" "mythes-$LSUP" \
        "libreoffice-langpack-$LSUP" "libreoffice-help-$LSUP"
      ;;
    arch)
      # Arch has no metapackage for a language at all - every translation is
      # its own package, and LibreOffice's follows whichever base is installed.
      if pacman -Qq libreoffice-still >/dev/null 2>&1; then LO="libreoffice-still-$LSUP"
      else                                                  LO="libreoffice-fresh-$LSUP"; fi
      pkg_install_available \
        "hunspell-$LSUP" "hyphen-$LSUP" "mythes-$LSUP" "$LO" \
        "firefox-i18n-$LSUP" "thunderbird-i18n-$LSUP"
      ;;
    debian)
      # Debian has no language-pack-* - those are Ubuntu's - and its Firefox
      # is the ESR build, with the translations named after it.
      pkg_install_available \
        "hunspell-$LSUP" "hyphen-$LSUP" "mythes-$LSUP" \
        "libreoffice-l10n-$LSUP" "libreoffice-help-$LSUP" \
        "firefox-esr-l10n-$LSUP" "firefox-l10n-$LSUP" "thunderbird-l10n-$LSUP"
      ;;
    *)
      pkg_install_available \
        "language-pack-$LSUP" "language-pack-gnome-$LSUP" \
        "hunspell-$LSUP" "hyphen-$LSUP" "mythes-$LSUP" \
        "libreoffice-l10n-$LSUP" "libreoffice-help-$LSUP" \
        "firefox-locale-$LSUP" "thunderbird-locale-$LSUP"
      ;;
  esac

  # Mint and Ubuntu know which packages a language really needs - including the
  # ones whose names follow no pattern at all. Debian has it too where
  # language-selector-common happens to be installed; Fedora's langpacks-XX
  # covers the same ground, and Arch has nothing of the kind.
  if [ "$PKG" = apt ] && command -v check-language-support >/dev/null 2>&1; then
    extra="$(check-language-support -l "$LSUP" 2>/dev/null || true)"
    if [ -n "$extra" ]; then
      # shellcheck disable=SC2086
      pkg_install_available $extra
    fi
  fi
fi

# ---------- desktop look ------------------------------------------------------
# A dropped connection, a renamed repo, or GitHub being briefly unreachable is
# routine - not a reason to take the whole run down. Every call site here is a
# bare statement, so under `set -e` a plain non-zero from git would have ended
# the script right there; this always returns 0 and warns instead, leaving the
# usual "theme not found" handling further down to notice the empty directory
# and say so, the same way it would for any other missing theme. A flaky link
# gets a couple of retries before that.
clone() {                          # clone URL DEST
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry]%s git clone %s\n' "$C_Y" "$C_0" "$1"; return 0; fi
  rm -rf "$2"
  local tries=0
  until git clone --depth=1 -q "$1" "$2" 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge 3 ]; then
      warn "$(fmt "$M_CLONEFAIL" "$1")"
      rm -rf "$2"
      return 0
    fi
    sleep 2
  done
  return 0
}

# Like gset, but for a schema that is not installed system-wide - a GNOME
# extension keeps its own in the folder it was installed into.
gset_dir() {                       # gset_dir SCHEMADIR SCHEMA KEY VALUE
  [ "$DRY_RUN" = 1 ] && { printf '  %s[dry]%s gsettings set %s %s %s\n' "$C_Y" "$C_0" "$2" "$3" "$4"; return 0; }
  gsettings --schemadir "$1" set "$2" "$3" "$4" 2>/dev/null \
    || warn "$(fmt "$M_GSETFAIL" "$2" "$3")"
  return 0
}

# Where a theme of that name actually landed, if anywhere.
find_dir() {                       # find_dir themes|icons NAME -> path
  local kind="$1" name="$2" d
  [ -n "$name" ] || return 1
  for d in "$HOME/.$kind" "$HOME/.local/share/$kind" "/usr/share/$kind"; do
    [ -d "$d/$name" ] && { printf '%s\n' "$d/$name"; return 0; }
  done
  return 1
}

# Fallback if upstream renames a variant: take the first NAME* we can find.
pick_prefix() {                    # pick_prefix themes|icons PREFIX -> name
  local kind="$1" prefix="${2%%-*}" d hit
  for d in "$HOME/.$kind" "$HOME/.local/share/$kind" "/usr/share/$kind"; do
    [ -d "$d" ] || continue
    hit="$(find "$d" -maxdepth 1 -mindepth 1 -type d -name "${prefix}*" -printf '%f\n' 2>/dev/null | sort | head -1)"
    [ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
  done
  return 1
}

if [ "$DO_THEME" = 1 ] && [ "$STYLE" != none ]; then
  step "$(fmt "$S_THEME" "$STYLE" "$VARIANT")"

  GTK_THEME=""; ICON_THEME=""

  if [ "$STYLE" = mint ]; then
    # Already on the machine on Mint. Nothing to download, nothing that can
    # half-install. Fedora packages the same themes for its Cinnamon spin, so
    # try those - and if they are not there either, fall back to the theme
    # every GTK desktop has.
    if [ "$VARIANT" = dark ]; then GTK_THEME="Mint-Y-Dark"; else GTK_THEME="Mint-Y"; fi
    ICON_THEME="Mint-Y"
    # Only Mint and Ubuntu have these on the machine already. Everywhere else
    # it is worth asking the archive - and falling back to Adwaita if it says no.
    if [ "$DISTRO" != mint ] && ! find_dir themes "$GTK_THEME" >/dev/null 2>&1; then
      pkg_install_available mint-themes mint-y-icons
    fi
    if [ "$DRY_RUN" = 0 ] && ! find_dir themes "$GTK_THEME" >/dev/null 2>&1; then
      if [ "$VARIANT" = dark ]; then GTK_THEME="Adwaita-dark"; else GTK_THEME="Adwaita"; fi
      ICON_THEME="Adwaita"
    fi
    ok "$M_MINTTHEME"

  elif [ "$STYLE" = arc ]; then
    # Arc is packaged on both families, so there is nothing to clone and no
    # stylesheet to build - and Papirus is the icon set it is usually paired
    # with. Whichever of the two the archive is missing gets skipped, and the
    # name fallback below picks up whatever did land.
    case "$PKG" in
      pacman) pkg_install_available arc-gtk-theme papirus-icon-theme ;;
      *)      pkg_install_available arc-theme     papirus-icon-theme ;;
    esac
    if [ "$VARIANT" = dark ]; then GTK_THEME="Arc-Dark";  ICON_THEME="Papirus-Dark"
    else                           GTK_THEME="Arc";       ICON_THEME="Papirus"; fi

  else
    # These themes are built from Sass at install time. Without sassc the
    # installer writes a theme directory with no usable stylesheet - which is
    # exactly what an "ugly grey theme" is. Dependencies first, always.
    case "$PKG" in
      dnf)    pkg_install_available git sassc gnome-themes-extra gtk-murrine-engine \
                                    glib2-devel libxml2 ;;
      pacman) pkg_install_available git sassc gnome-themes-extra gtk-engine-murrine \
                                    glib2 libxml2 ;;
      *)      pkg_install_available git sassc gnome-themes-extra gtk2-engines-murrine \
                                    libglib2.0-dev-bin libgio-2.0-dev-bin libxml2-utils ;;
    esac

    mkdir -p "$WORKDIR" "$HOME/.themes" "$HOME/.icons"

    # </dev/null on every upstream installer: stdin here is whatever is left of
    # the curl pipe, and an installer that decides to ask something would hang.
    if [ "$STYLE" = win11 ]; then
      clone https://github.com/vinceliuice/Fluent-gtk-theme.git  "$WORKDIR/fluent-gtk"
      clone https://github.com/vinceliuice/Fluent-icon-theme.git "$WORKDIR/fluent-icons"
      if [ "$DRY_RUN" = 0 ]; then
        ( cd "$WORKDIR/fluent-gtk"   && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Fluent GTK")"
        ( cd "$WORKDIR/fluent-icons" && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Fluent icons")"
      fi
      if [ "$VARIANT" = dark ]; then GTK_THEME="Fluent-Dark"; ICON_THEME="Fluent-dark"
      else                            GTK_THEME="Fluent-Light"; ICON_THEME="Fluent"; fi

    elif [ "$STYLE" = mac ]; then
      clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git  "$WORKDIR/whitesur-gtk"
      clone https://github.com/vinceliuice/WhiteSur-icon-theme.git "$WORKDIR/whitesur-icons"
      if [ "$DRY_RUN" = 0 ]; then
        note "$M_BIGTHEME"
        ( cd "$WORKDIR/whitesur-gtk"   && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "WhiteSur GTK")"
        ( cd "$WORKDIR/whitesur-icons" && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "WhiteSur icons")"
      fi
      if [ "$VARIANT" = dark ]; then GTK_THEME="WhiteSur-Dark"; ICON_THEME="WhiteSur-dark"
      else                            GTK_THEME="WhiteSur-Light"; ICON_THEME="WhiteSur"; fi

    elif [ "$STYLE" = orchis ]; then
      clone https://github.com/vinceliuice/Orchis-theme.git "$WORKDIR/orchis"
      if [ "$DRY_RUN" = 0 ]; then
        ( cd "$WORKDIR/orchis" && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Orchis")"
      fi
      # No icon set of its own, so it borrows the one it is usually seen with.
      pkg_install_available papirus-icon-theme
      if [ "$VARIANT" = dark ]; then GTK_THEME="Orchis-Dark";  ICON_THEME="Papirus-Dark"
      else                           GTK_THEME="Orchis-Light"; ICON_THEME="Papirus"; fi

    elif [ "$STYLE" = colloid ]; then
      clone https://github.com/vinceliuice/Colloid-gtk-theme.git  "$WORKDIR/colloid-gtk"
      clone https://github.com/vinceliuice/Colloid-icon-theme.git "$WORKDIR/colloid-icons"
      if [ "$DRY_RUN" = 0 ]; then
        ( cd "$WORKDIR/colloid-gtk"   && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Colloid GTK")"
        ( cd "$WORKDIR/colloid-icons" && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Colloid icons")"
      fi
      if [ "$VARIANT" = dark ]; then GTK_THEME="Colloid-Dark";  ICON_THEME="Colloid-Dark"
      else                           GTK_THEME="Colloid-Light"; ICON_THEME="Colloid"; fi

    elif [ "$STYLE" = graphite ]; then
      clone https://github.com/vinceliuice/Graphite-gtk-theme.git "$WORKDIR/graphite"
      if [ "$DRY_RUN" = 0 ]; then
        ( cd "$WORKDIR/graphite" && ./install.sh </dev/null >/dev/null ) || warn "$(fmt "$M_THEMEFAIL" "Graphite")"
      fi
      pkg_install_available papirus-icon-theme
      if [ "$VARIANT" = dark ]; then GTK_THEME="Graphite-Dark";  ICON_THEME="Papirus-Dark"
      else                           GTK_THEME="Graphite-Light"; ICON_THEME="Papirus"; fi

    elif [ "$STYLE" = nordic ]; then
      # Nordic is a plain theme directory - nothing to build, so it goes
      # straight into ~/.themes the way the Windows 10 one does. It is a dark
      # theme first; Nordic-Polar is the light one.
      if [ "$VARIANT" = dark ]; then
        clone https://github.com/EliverLara/Nordic.git "$HOME/.themes/Nordic"
        [ "$DRY_RUN" = 1 ] || rm -rf "$HOME/.themes/Nordic/.git"
        GTK_THEME="Nordic";       ICON_THEME="Papirus-Dark"
      else
        # Polar is the light one, and it is a repository of its own rather
        # than a variant inside Nordic.
        clone https://github.com/EliverLara/Nordic-Polar.git "$HOME/.themes/Nordic-Polar"
        [ "$DRY_RUN" = 1 ] || rm -rf "$HOME/.themes/Nordic-Polar/.git"
        GTK_THEME="Nordic-Polar"; ICON_THEME="Papirus"
      fi
      pkg_install_available papirus-icon-theme

    else
      clone https://github.com/B00merang-Project/Windows-10.git "$HOME/.themes/Windows-10"
      clone https://github.com/B00merang-Artwork/Windows-10.git "$HOME/.icons/Windows-10"
      [ "$DRY_RUN" = 1 ] || rm -rf "$HOME/.themes/Windows-10/.git" "$HOME/.icons/Windows-10/.git"
      GTK_THEME="Windows-10"; ICON_THEME="Windows-10"
    fi
  fi

  if [ "$DRY_RUN" = 1 ]; then
    note "$(fmt "$M_WOULDSET" "$GTK_THEME" "$ICON_THEME")"
  elif ! desktop_reachable; then
    warn "$(fmt "$M_NOAPPLY" "$DESKLABEL")"
  elif [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
       && [ "$DESKTOP" != plasma ] && [ "$DESKTOP" != other ]; then
    # settings.ini is a file, so those two do not need a session bus.
    warn "$M_NOSESS1"
    warn "$M_NOSESS2"
  else
    tdir="$(find_dir themes "$GTK_THEME" || true)"
    if [ -z "$tdir" ]; then
      alt="$(pick_prefix themes "$GTK_THEME" || true)"
      if [ -n "$alt" ]; then GTK_THEME="$alt"; tdir="$(find_dir themes "$alt" || true)"; fi
    fi

    if [ -z "$tdir" ]; then
      warn "$M_NOTHEME1"
      warn "$M_NOTHEME2"
    else
      # Only set what this theme can actually deliver. Pointing Cinnamon at a
      # theme with no cinnamon/cinnamon.css is what leaves the panel grey.
      if [ -d "$tdir/gtk-3.0" ]; then
        set_gtk_theme "$GTK_THEME"
      else
        warn "$(fmt "$M_NOGTK" "$GTK_THEME")"
      fi
      if [ -d "$tdir/metacity-1" ]; then
        set_wm_theme "$GTK_THEME"
      fi
      # The panel is styled by the theme's cinnamon/ part, and that part rots
      # fast: Cinnamon renames its CSS classes between major versions, so a
      # shell theme written for Cinnamon 2.x styles almost nothing on 6.x and
      # the panel comes out unstyled grey. Themes carrying info.json record
      # when they were last touched, so we can refuse the ancient ones.
      # None of it applies anywhere else: no other desktop here has a shell
      # theme this script can point at.
      STALE_BEFORE=1546300800          # 2019-01-01; Cinnamon 4.0 era
      SHELL_THEME=""
      if [ "$DESKTOP" != cinnamon ]; then
        note "$(fmt "$M_NOSHELL" "$DESKLABEL")"
      elif [ -f "$tdir/cinnamon/cinnamon.css" ]; then
        # Guard the file test separately: with pipefail on, a sed that fails
        # because the file is absent would take the whole script down.
        edited=""
        if [ -f "$tdir/cinnamon/info.json" ]; then
          edited="$(sed -n 's/.*"last-edited"[^0-9]*\([0-9]\{6,\}\).*/\1/p' \
                    "$tdir/cinnamon/info.json" | head -1 || true)"
        fi
        if [ -n "$edited" ] && [ "$edited" -lt "$STALE_BEFORE" ] 2>/dev/null; then
          year="$(date -u -d "@$edited" '+%Y' 2>/dev/null || echo '?')"
          note "$(fmt "$M_STALE1" "$GTK_THEME" "$year")"
          note "$M_STALE2"
        else
          SHELL_THEME="$GTK_THEME"
        fi
      else
        note "$(fmt "$M_NOCINN" "$GTK_THEME")"
      fi

      if [ -z "$SHELL_THEME" ] && [ "$DESKTOP" = cinnamon ]; then
        # Windows 10's own taskbar is dark, so dark is the closer match anyway.
        if [ "$STYLE" = win10 ] || [ "$VARIANT" = dark ]; then
          fallbacks="Mint-Y-Dark Mint-Y"
        else
          fallbacks="Mint-Y Mint-Y-Dark"
        fi
        for cand in $fallbacks; do
          cdir="$(find_dir themes "$cand" || true)"
          if [ -n "$cdir" ] && [ -f "$cdir/cinnamon/cinnamon.css" ]; then
            SHELL_THEME="$cand"; break
          fi
        done
      fi

      if [ -n "$SHELL_THEME" ]; then
        gset org.cinnamon.theme name "$SHELL_THEME"
      elif [ "$DESKTOP" = cinnamon ]; then
        note "$M_NOPANEL"
      fi

      if find_dir icons "$ICON_THEME" >/dev/null 2>&1; then
        set_icon_theme "$ICON_THEME"
      else
        alt="$(pick_prefix icons "$ICON_THEME" || true)"
        if [ -n "$alt" ]; then
          ICON_THEME="$alt"; set_icon_theme "$ICON_THEME"
        else
          warn "$(fmt "$M_NOICONS" "$ICON_THEME")"
        fi
      fi
      ok "$(fmt "$M_THEMESET" "$GTK_THEME" "${SHELL_THEME:-$M_UNTOUCHED}" "$ICON_THEME")"
    fi
  fi
fi

# ---------- the menu button ---------------------------------------------------
# The menu is its own choice, not a side effect of the layout: you can want a
# Zorin-style menu on a perfectly ordinary panel. What the panel rewrite in the
# Windows 11 layout points at, unless one of the branches below changes it:
APPLET_UUID="menu@cinnamon.org"

if [ "$MENU" != system ]; then
  step "$S_MENU"
  if [ "$MENU" = cinnamenu ] && [ "$DESKTOP" = cinnamon ]; then
    # Cinnamon's own menu is a classic two-column list. Cinnamenu is the
    # maintained applet that comes closest to a tiled start menu with search.
    if [ "$DRY_RUN" = 1 ]; then
      printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$M_GETMENU"
      APPLET_UUID="Cinnamenu@json"
    else
      pkg_install_available git
      mkdir -p "$HOME/.local/share/cinnamon/applets"
      # The spices repo holds every applet there is, so check out just this one.
      if git clone --depth=1 --filter=blob:none --sparse -q \
             https://github.com/linuxmint/cinnamon-spices-applets.git "$WORKDIR/spices" 2>/dev/null \
         && ( cd "$WORKDIR/spices" && git sparse-checkout set "Cinnamenu@json" >/dev/null 2>&1 ) \
         && [ -d "$WORKDIR/spices/Cinnamenu@json/files/Cinnamenu@json" ]; then
        cp -r "$WORKDIR/spices/Cinnamenu@json/files/Cinnamenu@json" \
              "$HOME/.local/share/cinnamon/applets/"
        APPLET_UUID="Cinnamenu@json"
        ok "$M_CINNAMENU"
      else
        warn "$M_NOCINNAMENU"
      fi
    fi

  elif [ "$MENU" = zorin ] && [ "$DESKTOP" = gnome ]; then
    # Zorin OS's own menu extension is not published outside their Ubuntu
    # archive, and the "Z" on its button is a Zorin trademark. ArcMenu is that
    # same menu's descendant - it was forked from Zorin's extension in 2017,
    # and its default layout is still the one drawn after the Zorin OS menu -
    # and unlike Zorin's it is kept current with GNOME.
    case "$PKG" in
      dnf)    pkg_install_available git make gettext glib2-devel ;;
      pacman) pkg_install_available git make gettext glib2 ;;
      *)      pkg_install_available git make gettext \
                                    libglib2.0-dev-bin libgio-2.0-dev-bin libglib2.0-bin ;;
    esac
    ARC_UUID="arcmenu@arcmenu.com"
    ARC_DIR="$HOME/.local/share/gnome-shell/extensions/$ARC_UUID"
    if [ "$DRY_RUN" = 1 ]; then
      printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$M_ARCENABLE"
      note "$(fmt "$M_ARCICON" "$MENU_ICON")"
    else
      clone https://gitlab.com/arcmenu/ArcMenu.git "$WORKDIR/arcmenu"
      # An extension declares which GNOME versions it knows. Running one on a
      # shell outside that list is exactly how an extension ends up installed
      # and silently not loading, so say it out loud beforehand.
      gv="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
      sv="$(sed -n '/"shell-version"/,/]/p' "$WORKDIR/arcmenu/metadata.json" 2>/dev/null \
            | tr -dc '0-9 ' | tr -s ' ' | sed 's/^ *//;s/ *$//' || true)"
      if [ -n "$gv" ] && [ -n "$sv" ]; then
        case " $sv " in *" $gv "*) ;; *) warn "$(fmt "$M_ARCOLD" "$sv" "$gv")" ;; esac
      fi
      # Builds the resources, schemas and translations, then copies the lot
      # into your home directory - nothing lands in the system.
      if ( cd "$WORKDIR/arcmenu" && make install >/dev/null 2>&1 ); then
        ok "$M_ARCMENU"
        gset_dir "$ARC_DIR/schemas" org.gnome.shell.extensions.arcmenu \
                 menu-layout arcmenu
        # menu-button-icon takes an icon name, so hand it the desktop's own
        # generic system icon rather than the logo the extension ships with.
        # It follows whichever icon theme is set above, like every other icon.
        gset_dir "$ARC_DIR/schemas" org.gnome.shell.extensions.arcmenu \
                 menu-button-icon "$MENU_ICON"
        ok "$(fmt "$M_ARCICON" "$MENU_ICON")"
        if command -v gnome-extensions >/dev/null 2>&1; then
          gnome-extensions enable "$ARC_UUID" 2>/dev/null || warn "$M_ARCNOENABLE"
        else
          warn "$M_ARCNOENABLE"
        fi
      else
        warn "$M_ARCMENUFAIL"
      fi
    fi

  else
    warn "$(fmt "$M_MENUWRONG" "$DESKLABEL")"
  fi
fi

# ---------- traditional desktop ----------------------------------------------
if [ "$LAYOUT" = traditional ]; then
  step "$S_CLASSIC"
  set_clock_24h
  set_button_layout right
  # Only claim what this desktop actually got.
  case "$DESKTOP" in
    cinnamon)
      gset org.cinnamon panels-height "['1:40']"
      gset org.cinnamon.desktop.interface first-day-of-week 1 || true
      ok "$M_CLASSICOK" ;;
    gnome|xfce|mate)
      note "$(fmt "$M_DESKPANEL" "$DESKLABEL")"
      ok "$M_BUTTONS_R" ;;
    *)
      note "$(fmt "$M_DESKNONE" "$DESKLABEL")" ;;
  esac
fi

# ---------- Windows 11-style desktop: centred taskbar, grid start menu ------
if [ "$LAYOUT" = win11 ]; then
  step "$S_WIN11"

  set_clock_24h
  set_button_layout right

  # Everything past this point is Cinnamon's panel. No other desktop here has
  # an equivalent this script can drive, so say so instead of failing quietly.
  WIN11_PANEL=0
  case "$DESKTOP" in
    cinnamon)        WIN11_PANEL=1 ;;
    gnome|xfce|mate) note "$(fmt "$M_DESKPANEL" "$DESKLABEL")"; ok "$M_BUTTONS_R" ;;
    *)               note "$(fmt "$M_DESKNONE" "$DESKLABEL")" ;;
  esac
fi

if [ "${WIN11_PANEL:-0}" = 1 ]; then
  # Windows 11 centres the taskbar. Cinnamon stores each applet as
  # panel:zone:order:uuid, so move the menu, the window list and show-desktop
  # into the centre zone and leave the system tray on the right where it is.
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$M_MOVEMENU"
  else
    cur="$(gsettings get org.cinnamon enabled-applets 2>/dev/null || echo '')"
    case "$cur" in
      *:menu@cinnamon.org*|*:Cinnamenu@json*)
        gset org.cinnamon enabled-applets "$(printf '%s' "$cur" \
          | sed "s/:menu@cinnamon\.org/:${APPLET_UUID}/g" \
          | sed -E "s/(panel[0-9]+):left:([0-9]+):(Cinnamenu@json|menu@cinnamon\.org|grouped-window-list@cinnamon\.org|window-list@cinnamon\.org|show-desktop@cinnamon\.org)/\1:center:\2:\3/g")"
        panel_id="$(printf '%s' "$cur" | grep -oE 'panel[0-9]+' | head -1 | sed 's/panel//' || true)"
        [ -n "$panel_id" ] || panel_id=1
        gset org.cinnamon panels-height "['${panel_id}:44']"
        ;;
      *)
        warn "$M_NOAPPLETS"
        ;;
    esac
  fi

  ok "$M_WIN11OK"
fi

# ---------- macOS-style desktop: menu bar on top, dock at the bottom ---------
if [ "$LAYOUT" = mac ]; then
  step "$S_MAC"

  # On a Mac the window buttons sit on the left.
  set_button_layout left
  set_clock_24h

  # Move Cinnamon's own panel to the top and slim it into a menu bar. Read the
  # current setting and rewrite only the position, so the panel's id and
  # monitor number stay whatever this machine already had. GNOME's top bar is
  # already where this wants it, so there it is only the dock that is missing.
  if [ "$DESKTOP" != cinnamon ]; then
    case "$DESKTOP" in
      gnome|xfce|mate) note "$(fmt "$M_DESKPANEL" "$DESKLABEL")" ;;
      *)               note "$(fmt "$M_DESKNONE" "$DESKLABEL")" ;;
    esac
  elif [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$M_MOVEPANEL"
  else
    cur="$(gsettings get org.cinnamon panels-enabled 2>/dev/null || echo '')"
    case "$cur" in
      *:bottom*|*:top*)
        gset org.cinnamon panels-enabled "$(printf '%s' "$cur" | sed "s/:bottom'/:top'/g")"
        panel_id="$(printf '%s' "$cur" | sed -n "s/^\['\([0-9][0-9]*\):.*/\1/p")"
        [ -n "$panel_id" ] || panel_id=1
        gset org.cinnamon panels-height "['${panel_id}:28']"
        ;;
      *)
        warn "$M_NOPANELCFG"
        ;;
    esac
  fi

  # The dock.
  pkg_install_available plank
  if [ "$DRY_RUN" = 1 ] || command -v plank >/dev/null 2>&1; then
    PLANK=net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/
    gset "$PLANK" theme "Transparent"
    gset "$PLANK" position "bottom"
    gset "$PLANK" alignment "center"
    gset "$PLANK" icon-size 48
    gset "$PLANK" zoom-enabled true
    gset "$PLANK" zoom-percent 150
    gset "$PLANK" hide-mode "intelligent"

    if [ "$DRY_RUN" = 1 ]; then
      printf '  %s[dry]%s %s\n' "$C_Y" "$C_0" "$M_WRITEAUTO"
    else
      mkdir -p "$HOME/.config/autostart"
      cat > "$HOME/.config/autostart/plank.desktop" <<'PLANKEOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=Dock
Exec=plank
Icon=plank
Terminal=false
X-GNOME-Autostart-enabled=true
PLANKEOF
      # ...and start it now, if there is a session to start it in.
      if [ -n "${DISPLAY:-}" ] && ! pgrep -x plank >/dev/null 2>&1; then
        nohup plank >/dev/null 2>&1 &
      fi
    fi
    ok "$M_DOCKOK"
  else
    warn "$M_NOPLANK"
  fi

  case "$DESKTOP" in
    cinnamon)        ok "$M_MACOK" ;;
    gnome|xfce|mate) ok "$M_BUTTONS_L" ;;
  esac
fi

# ---------- done --------------------------------------------------------------
step "$S_DONE"
if [ "$DRY_RUN" = 0 ]; then
  mkdir -p "${SUMMARY_FILE%/*}" 2>/dev/null || true
  { printf '%s  kasper.sh/linux %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')" "$SCRIPT_VERSION"
    summary_lines; } > "$SUMMARY_FILE" 2>/dev/null || true
  [ -f "$SUMMARY_FILE" ] && note "$(fmt "$M_LOGGED" "$SUMMARY_FILE")"
fi
cat <<EOF
  $D_DONE1
  $D_DONE2

  $D_DONE3
  $D_DONE4
    curl -fsSL https://kasper.sh/linux/install.sh | bash

  $D_DONE5
    localectl status
    locale
    $CHECK_CMD
EOF
