#!/usr/bin/env bash

################################################################################
# Lunigy AI Autonomous System - Bootstrap Installer
#
# Version: 2.0.0
# Purpose: Single-command installation for public use
# Usage: bash <(curl -sSL https://raw.githubusercontent.com/lunigy/install/main/bootstrap.sh)
#
# This script:
# 1. Downloads the full installation script from main repo
# 2. Executes with provided arguments
# 3. Cleans up temporary files
#
# Features:
# - Automatic dashboard setup
# - Local-first storage (no Firebase required)
# - Comprehensive validation
# - RAG system (optional)
################################################################################

set -e
set -u
set -o pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Configuration
readonly BOOTSTRAP_VERSION="2.0.0"
readonly INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/lunigy/install/main/install.sh"
readonly REPO_URL="https://github.com/lunigy/ai-autonomous-system.git"
readonly TEMP_SCRIPT="/tmp/lunigy-install-$$.sh"

################################################################################
# Functions
################################################################################

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║     Lunigy AI Autonomous System - Bootstrap Installer         ║"
    echo "║                    Version $BOOTSTRAP_VERSION                           ║"
    echo "║                                                                ║"
    echo "║  🤖 7 Layers of Intelligence for Building Products            ║"
    echo "║  🎯 Dashboard included for real-time visibility               ║"
    echo "║  🧠 RAG-powered context management                            ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

cleanup() {
    if [ -f "$TEMP_SCRIPT" ]; then
        rm -f "$TEMP_SCRIPT"
    fi
}

trap cleanup EXIT

check_prerequisites() {
    info "Checking prerequisites..."

    local errors=0

    # Check curl
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed"
        info "Install: apt-get install curl (Ubuntu) or brew install curl (macOS)"
        errors=$((errors + 1))
    fi

    # Check bash
    if ! command -v bash &> /dev/null; then
        error "bash is required but not installed"
        errors=$((errors + 1))
    fi

    # Check Node.js (not required now, but will be needed)
    if ! command -v node &> /dev/null; then
        warning "Node.js not found - will be required for dashboard"
        info "Install from: https://nodejs.org/ (v18+ recommended)"
    else
        success "Node.js $(node -v) found"
    fi

    # Check Python (not required now, but will be needed)
    if ! command -v python3 &> /dev/null; then
        warning "Python not found - will be required for hooks"
        info "Install from: https://python.org/ (v3.9+ recommended)"
    else
        success "Python $(python3 --version | cut -d' ' -f2) found"
    fi

    # Check Git (not required now, but will be needed)
    if ! command -v git &> /dev/null; then
        warning "Git not found - will be required"
        info "Install from: https://git-scm.com/"
    else
        success "Git $(git --version | cut -d' ' -f3) found"
    fi

    if [ $errors -gt 0 ]; then
        error "\nCannot proceed - missing required tools"
        exit 1
    fi

    success "Bootstrap prerequisites met"
}

################################################################################
# Main
################################################################################

main() {
    print_header

    check_prerequisites
    echo ""

    # Download installation script
    info "Downloading installation script..."
    if curl -fsSL "$INSTALL_SCRIPT_URL" -o "$TEMP_SCRIPT"; then
        success "Installation script downloaded"
    else
        error "Failed to download installation script from: $INSTALL_SCRIPT_URL"
        info "This could be due to:"
        info "  - Network connectivity issues"
        info "  - GitHub is down"
        info "  - Repository is private or moved"
        exit 1
    fi

    # Make executable
    chmod +x "$TEMP_SCRIPT"
    echo ""

    # Check if --repo-url provided
    local has_repo_url=false
    for arg in "$@"; do
        if [[ "$arg" =~ ^--repo-url ]]; then
            has_repo_url=true
            break
        fi
    done

    # Execute installation script
    info "Starting installation..."
    echo ""
    echo -e "${BOLD}What will be installed:${NC}"
    echo "  ✅ Autonomous system (7 layers of intelligence)"
    echo "  ✅ Claude Code hooks (9 hooks)"
    echo "  ✅ Specialized agents (19 agents + 30 commands + 13 skills)"
    echo "  ✅ Health dashboard (http://localhost:3000)"
    echo "  ✅ RAG system (optional but recommended)"
    echo "  ✅ Knowledge base (regulations, learnings)"
    echo ""

    if [ "$has_repo_url" = false ]; then
        # Add default repo URL
        bash "$TEMP_SCRIPT" --repo-url="$REPO_URL" "$@"
    else
        # Use provided arguments
        bash "$TEMP_SCRIPT" "$@"
    fi

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo ""
        echo -e "${GREEN}${BOLD}"
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                                                                ║"
        echo "║              ✨ Installation Complete! ✨                      ║"
        echo "║                                                                ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
        echo -e "${BOLD}🎯 What's Next:${NC}"
        echo ""
        echo "  1. Verify system:"
        echo "     ${BLUE}bash .autonomous-system/scripts/validate-system.sh${NC}"
        echo ""
        echo "  2. Open your dashboard:"
        echo "     ${BLUE}http://localhost:3000${NC}"
        echo ""
        echo "  3. Open Claude Code:"
        echo "     ${BLUE}code .${NC} or ${BLUE}cursor .${NC}"
        echo ""
        echo "  4. Create your first user story:"
        echo "     Say: \"Add authentication feature\""
        echo ""
        echo "  5. Watch it appear in the dashboard!"
        echo ""
        echo -e "${BOLD}📖 Documentation:${NC}"
        echo "     .autonomous-system/docs/INSTALLATION-GUIDE.md"
        echo "     .autonomous-system/docs/DASHBOARD-INTEGRATION.md"
        echo ""
        echo -e "${BOLD}💡 Pro Tips:${NC}"
        echo "     • Keep dashboard open in browser tab"
        echo "     • Try: /discovery for market research"
        echo "     • Try: /engineering for development"
        echo "     • Try: /launch for marketing automation"
        echo ""
        echo -e "${GREEN}Happy building! 🚀${NC}"
        echo ""
    else
        echo ""
        error "Installation failed with exit code $exit_code"
        echo ""
        echo "Please check the error messages above."
        echo ""
        echo -e "${BOLD}Common issues:${NC}"
        echo "  • Missing prerequisites (Node.js, Python, Git)"
        echo "  • Network connectivity"
        echo "  • Insufficient permissions"
        echo "  • Repository not accessible"
        echo ""
        echo -e "${BOLD}Get help:${NC}"
        echo "  📖 https://github.com/lunigy/ai-autonomous-system/issues"
        echo "  📧 Or check the troubleshooting guide in docs/"
        echo ""
        exit $exit_code
    fi
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat << EOF
Lunigy AI Autonomous System - Bootstrap Installer

USAGE:
    bash <(curl -sSL https://raw.githubusercontent.com/lunigy/install/main/bootstrap.sh) [OPTIONS]

OPTIONS:
    --config <type>         Configuration: minimal, full (default: full)
    --skip-dashboard        Skip health dashboard installation
    --skip-rag              Skip RAG system installation
    --rag-hooks             Install RAG auto-indexing git hooks
    --rag-index             Run initial RAG index
    --skip-prompts          Non-interactive mode
    --dry-run               Show what would be done
    --help                  Show this help

EXAMPLES:
    # Standard installation (recommended)
    bash <(curl -sSL https://raw.githubusercontent.com/lunigy/install/main/bootstrap.sh)

    # Full installation with RAG
    bash <(curl -sSL https://raw.githubusercontent.com/lunigy/install/main/bootstrap.sh) \\
      --config=full --rag-hooks --rag-index

    # Minimal installation (headless/CI)
    bash <(curl -sSL https://raw.githubusercontent.com/lunigy/install/main/bootstrap.sh) \\
      --config=minimal --skip-dashboard --skip-prompts

REQUIREMENTS:
    - Node.js v18+
    - Python 3.9+
    - Git 2.30+
    - ANTHROPIC_API_KEY (recommended)

FEATURES:
    ✅ 7 layers of intelligence
    ✅ Health dashboard (real-time visibility)
    ✅ Local-first storage (no Firebase required)
    ✅ RAG system (67% cost reduction)
    ✅ Regulatory validation (prevents costly mistakes)
    ✅ Continuous learning (auto-improvement)

MORE INFO:
    https://github.com/lunigy/ai-autonomous-system

EOF
    exit 0
fi

# Run main function
main "$@"
