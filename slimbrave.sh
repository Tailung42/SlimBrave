#!/bin/bash
# SlimBrave - Linux Version
# Must be run as root (sudo)

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
SALMON='\033[38;5;210m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Policy file path (Linux Brave managed policies) ──────────────────────────
POLICY_DIR="/etc/brave/policies/managed"
POLICY_FILE="$POLICY_DIR/slimbrave.json"

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] This script must be run as root.${RESET}"
    echo -e "    Run: ${CYAN}sudo bash SlimBrave.sh${RESET}"
    exit 1
fi

mkdir -p "$POLICY_DIR"

# ─── Feature definitions ──────────────────────────────────────────────────────
# Format: "display_name|json_key|json_value"

TELEMETRY_FEATURES=(
    "Disable Metrics Reporting|MetricsReportingEnabled|false"
    "Disable Safe Browsing Reporting|SafeBrowsingExtendedReportingEnabled|false"
    "Disable URL Data Collection|UrlKeyedAnonymizedDataCollectionEnabled|false"
    "Disable Feedback Surveys|FeedbackSurveysEnabled|false"
)

PRIVACY_FEATURES=(
    "Disable Safe Browsing|SafeBrowsingProtectionLevel|0"
    "Disable Autofill (Addresses)|AutofillAddressEnabled|false"
    "Disable Autofill (Credit Cards)|AutofillCreditCardEnabled|false"
    "Disable Password Manager|PasswordManagerEnabled|false"
    "Disable Browser Sign-in|BrowserSignin|0"
    "Disable WebRTC IP Leak|WebRtcIPHandling|\"disable_non_proxied_udp\""
    "Disable QUIC Protocol|QuicAllowed|false"
    "Block Third Party Cookies|BlockThirdPartyCookies|true"
    "Enable Do Not Track|EnableDoNotTrack|true"
    "Force Google SafeSearch|ForceGoogleSafeSearch|true"
    "Disable IPFS|IPFSEnabled|false"
    "Disable Incognito Mode|IncognitoModeAvailability|1"
    "Force Incognito Mode|IncognitoModeAvailability|2"
)

BRAVE_FEATURES=(
    "Disable Brave Rewards|BraveRewardsDisabled|true"
    "Disable Brave Wallet|BraveWalletDisabled|true"
    "Disable Brave VPN|BraveVPNDisabled|true"
    "Disable Brave AI Chat|BraveAIChatEnabled|false"
    "Disable Brave Shields|BraveShieldsDisabledForUrls|[\"https://*\", \"http://*\"]"
    "Disable Tor|TorDisabled|true"
    "Disable Sync|SyncDisabled|true"
)

PERF_FEATURES=(
    "Disable Background Mode|BackgroundModeEnabled|false"
    "Disable Media Recommendations|MediaRecommendationsEnabled|false"
    "Disable Shopping List|ShoppingListEnabled|false"
    "Always Open PDF Externally|AlwaysOpenPdfExternally|true"
    "Disable Translate|TranslateEnabled|false"
    "Disable Spellcheck|SpellcheckEnabled|false"
    "Disable Promotions|PromotionsEnabled|false"
    "Disable Search Suggestions|SearchSuggestEnabled|false"
    "Disable Printing|PrintingEnabled|false"
    "Disable Default Browser Prompt|DefaultBrowserSettingEnabled|false"
    "Disable Developer Tools|DeveloperToolsAvailability|2"
)

# ─── State: selected keys (associative array key=json_key, val=json_value) ────
declare -A SELECTED

# ─── Helpers ──────────────────────────────────────────────────────────────────
print_header() {
    clear
    echo -e "${SALMON}${BOLD}"
    echo "  ███████╗██╗     ██╗███╗   ███╗██████╗ ██████╗  █████╗ ██╗   ██╗███████╗"
    echo "  ██╔════╝██║     ██║████╗ ████║██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔════╝"
    echo "  ███████╗██║     ██║██╔████╔██║██████╔╝██████╔╝███████║██║   ██║█████╗  "
    echo "  ╚════██║██║     ██║██║╚██╔╝██║██╔══██╗██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝  "
    echo "  ███████║███████╗██║██║ ╚═╝ ██║██████╔╝██║  ██║██║  ██║ ╚████╔╝ ███████╗"
    echo "  ╚══════╝╚══════╝╚═╝╚═╝     ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝"
    echo -e "${RESET}"
    echo -e "  ${CYAN}Brave Browser Policy Manager for Linux${RESET}"
    echo -e "  Policy file: ${YELLOW}$POLICY_FILE${RESET}"
    echo ""
}

# Toggle selection for a feature group
select_group() {
    local -n group_ref=$1
    local group_name="$2"

    echo -e "\n${SALMON}${BOLD}  ── $group_name ──${RESET}"
    local i=1
    local keys=()
    local vals=()
    local names=()

    for entry in "${group_ref[@]}"; do
        IFS='|' read -r name key val <<< "$entry"
        keys+=("$key")
        vals+=("$val")
        names+=("$name")
        local status="${RED}[ ]${RESET}"
        if [[ -v SELECTED["$key"] ]]; then
            status="${GREEN}[x]${RESET}"
        fi
        echo -e "    ${status} ${i}) $name"
        ((i++))
    done

    echo ""
    echo -e "  Enter numbers to toggle (e.g. ${CYAN}1 3 4${RESET}), or press ${CYAN}Enter${RESET} to skip:"
    read -r -p "  > " choices

    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
            local idx=$((choice - 1))
            local k="${keys[$idx]}"
            local v="${vals[$idx]}"
            if [[ -v SELECTED["$k"] ]]; then
                unset SELECTED["$k"]
            else
                SELECTED["$k"]="$v"
            fi
        fi
    done
}

# ─── Apply settings → write JSON policy file ──────────────────────────────────
apply_settings() {
    if [[ ${#SELECTED[@]} -eq 0 && -z "$DNS_MODE" ]]; then
        echo -e "\n  ${YELLOW}[!] No settings selected. Nothing to apply.${RESET}"
        sleep 2
        return
    fi

    echo -e "\n  ${CYAN}Writing policy file...${RESET}"

    local json="{\n"
    local first=true

    for key in "${!SELECTED[@]}"; do
        local val="${SELECTED[$key]}"
        [[ "$first" == true ]] || json+=",\n"
        json+="  \"$key\": $val"
        first=false
    done

    if [[ -n "$DNS_MODE" ]]; then
        [[ "$first" == true ]] || json+=",\n"
        json+="  \"DnsOverHttpsMode\": \"$DNS_MODE\""
    fi

    json+="\n}"

    echo -e "$json" > "$POLICY_FILE"

    echo -e "  ${GREEN}[✓] Settings applied to: $POLICY_FILE${RESET}"
    echo -e "  ${YELLOW}Restart Brave to see changes.${RESET}"
    sleep 3
}

# ─── Export settings to JSON ──────────────────────────────────────────────────
export_settings() {
    read -r -p "  Enter export file path [~/SlimBraveSettings.json]: " export_path
    export_path="${export_path:-$HOME/SlimBraveSettings.json}"
    export_path="${export_path/#\~/$HOME}"

    local json="{\n  \"Features\": ["
    local first=true
    for key in "${!SELECTED[@]}"; do
        [[ "$first" == true ]] || json+=", "
        json+="\"$key\""
        first=false
    done
    json+="],\n  \"DnsMode\": \"${DNS_MODE:-}\"\n}"

    echo -e "$json" > "$export_path"
    echo -e "  ${GREEN}[✓] Exported to: $export_path${RESET}"
    sleep 2
}

# ─── Import settings from JSON ────────────────────────────────────────────────
import_settings() {
    read -r -p "  Enter import file path: " import_path
    import_path="${import_path/#\~/$HOME}"

    if [[ ! -f "$import_path" ]]; then
        echo -e "  ${RED}[!] File not found: $import_path${RESET}"
        sleep 2
        return
    fi

    # Requires jq
    if ! command -v jq &>/dev/null; then
        echo -e "  ${RED}[!] 'jq' is required for import. Install it with: sudo apt install jq${RESET}"
        sleep 3
        return
    fi

    SELECTED=()
    DNS_MODE=$(jq -r '.DnsMode // ""' "$import_path")

    # Re-map feature keys from import file back to values using all feature arrays
    local imported_keys
    mapfile -t imported_keys < <(jq -r '.Features[]' "$import_path" 2>/dev/null)

    for imported_key in "${imported_keys[@]}"; do
        for group in TELEMETRY_FEATURES PRIVACY_FEATURES BRAVE_FEATURES PERF_FEATURES; do
            local -n grp=$group
            for entry in "${grp[@]}"; do
                IFS='|' read -r name key val <<< "$entry"
                if [[ "$key" == "$imported_key" ]]; then
                    SELECTED["$key"]="$val"
                fi
            done
        done
    done

    echo -e "  ${GREEN}[✓] Imported from: $import_path${RESET}"
    sleep 2
}

# ─── Reset all settings ───────────────────────────────────────────────────────
reset_settings() {
    echo -e "\n  ${RED}${BOLD}Warning:${RESET} This will delete $POLICY_FILE and reset all Brave policies."
    read -r -p "  Are you sure? (yes/no): " confirm
    if [[ "$confirm" == "yes" ]]; then
        rm -f "$POLICY_FILE"
        SELECTED=()
        DNS_MODE=""
        echo -e "  ${GREEN}[✓] All Brave policy settings have been reset.${RESET}"
    else
        echo -e "  ${YELLOW}Reset cancelled.${RESET}"
    fi
    sleep 2
}

# ─── DNS mode selector ────────────────────────────────────────────────────────
set_dns_mode() {
    echo -e "\n${SALMON}${BOLD}  ── DNS Over HTTPS Mode ──${RESET}"
    echo -e "  Current: ${CYAN}${DNS_MODE:-not set}${RESET}"
    echo -e "  1) automatic"
    echo -e "  2) off"
    echo -e "  3) custom"
    echo -e "  4) clear / skip"
    read -r -p "  > " choice
    case "$choice" in
        1) DNS_MODE="automatic" ;;
        2) DNS_MODE="off" ;;
        3) DNS_MODE="custom" ;;
        4) DNS_MODE="" ;;
    esac
}

# ─── Show current selections summary ─────────────────────────────────────────
show_summary() {
    echo -e "\n${SALMON}${BOLD}  ── Selected Settings ──${RESET}"
    if [[ ${#SELECTED[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}None selected.${RESET}"
    else
        for key in "${!SELECTED[@]}"; do
            echo -e "  ${GREEN}[x]${RESET} $key = ${SELECTED[$key]}"
        done
    fi
    [[ -n "$DNS_MODE" ]] && echo -e "  ${GREEN}[x]${RESET} DnsOverHttpsMode = $DNS_MODE"
    echo ""
    read -r -p "  Press Enter to continue..."
}

# ─── Main menu ────────────────────────────────────────────────────────────────
DNS_MODE=""

while true; do
    print_header

    # Show quick selection count
    local_count=${#SELECTED[@]}
    echo -e "  ${BOLD}Selected: ${GREEN}$local_count setting(s)${RESET}  |  DNS Mode: ${CYAN}${DNS_MODE:-not set}${RESET}"
    echo ""
    echo -e "  ${SALMON}${BOLD}CONFIGURE:${RESET}"
    echo -e "  ${CYAN}1)${RESET} Telemetry & Reporting"
    echo -e "  ${CYAN}2)${RESET} Privacy & Security"
    echo -e "  ${CYAN}3)${RESET} Brave Features"
    echo -e "  ${CYAN}4)${RESET} Performance & Bloat"
    echo -e "  ${CYAN}5)${RESET} DNS Over HTTPS Mode"
    echo ""
    echo -e "  ${SALMON}${BOLD}ACTIONS:${RESET}"
    echo -e "  ${GREEN}6)${RESET} Apply Settings"
    echo -e "  ${YELLOW}7)${RESET} Export Settings"
    echo -e "  ${CYAN}8)${RESET} Import Settings"
    echo -e "  ${YELLOW}9)${RESET} Show Summary"
    echo -e "  ${RED}R)${RESET} Reset All Settings"
    echo -e "  ${RED}Q)${RESET} Quit"
    echo ""
    read -r -p "  Choose: " choice

    case "${choice,,}" in
        1) select_group TELEMETRY_FEATURES "Telemetry & Reporting" ;;
        2) select_group PRIVACY_FEATURES "Privacy & Security" ;;
        3) select_group BRAVE_FEATURES "Brave Features" ;;
        4) select_group PERF_FEATURES "Performance & Bloat" ;;
        5) set_dns_mode ;;
        6) apply_settings ;;
        7) export_settings ;;
        8) import_settings ;;
        9) show_summary ;;
        r) reset_settings ;;
        q) echo -e "\n  ${CYAN}Goodbye!${RESET}\n"; exit 0 ;;
        *) echo -e "  ${RED}Invalid choice.${RESET}"; sleep 1 ;;
    esac
done
