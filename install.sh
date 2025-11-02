#!/usr/bin/env bash

################################################################################
# Lunigy AI Autonomous System - Installation Script
#
# Version: 2.1.1
# Description: Automated installation of the autonomous system
# Usage: curl -sSL https://lunigy.ai/install.sh | bash
#        OR: bash install.sh [options]
#
# Options:
#   --config <minimal|full>  Configuration type (default: full)
#   --repo-url <url>         Repository URL (required)
#   --branch <name>          Branch name (default: main)
#   --skip-prompts           Use defaults without prompting
#   --dry-run                Show what would be done without doing it
#   --help                   Show this help message
#
# Requirements:
#   - Node.js v18+
#   - Python 3.9+
#   - Git 2.30+
#
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
SCRIPT_VERSION="2.1.1"
CONFIG_TYPE="full"
REPO_URL=""
BRANCH_NAME="main"
SKIP_PROMPTS=false
DRY_RUN=false
INSTALL_RAG=true           # Install RAG dependencies
SETUP_RAG_HOOKS=false      # Install RAG git hooks
RUN_RAG_INDEX=false        # Run initial RAG indexing

# State tracking
BACKUP_DIR=""
CHANGES_MADE=()

################################################################################
# Utility Functions
################################################################################

print_header() {
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║     Lunigy AI Autonomous System - Installation Script         ║"
    echo "║                    Version $SCRIPT_VERSION                           ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
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

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

step() {
    echo -e "\n${BOLD}▶ $1${NC}"
}

show_help() {
    cat << EOF
Lunigy AI Autonomous System - Installation Script v$SCRIPT_VERSION

USAGE:
    bash install.sh [OPTIONS]

OPTIONS:
    --config <type>         Configuration type: minimal, full (default: full)
    --repo-url <url>        Repository URL (required)
    --branch <name>         Branch name (default: main)
    --skip-prompts          Use defaults without prompting
    --dry-run               Show what would be done without doing it
    --skip-rag              Skip RAG system installation (not recommended)
    --rag-hooks             Install RAG auto-indexing git hooks
    --rag-index             Run initial RAG index after installation
    --help                  Show this help message

EXAMPLES:
    # Interactive installation (recommended)
    bash install.sh --repo-url=git@github.com:lunigy/ai-autonomous-system-system.git

    # Minimal configuration without prompts
    bash install.sh --repo-url=<url> --config=minimal --skip-prompts

    # Dry run to see what would happen
    bash install.sh --repo-url=<url> --dry-run

REQUIREMENTS:
    - Node.js v18+
    - Python 3.9+
    - Git 2.30+
    - ANTHROPIC_API_KEY environment variable (recommended)

For more information, visit: https://github.com/lunigy/ai-autonomous-system

EOF
    exit 0
}

################################################################################
# Prerequisites Checking
################################################################################

check_prerequisites() {
    step "Checking Prerequisites"

    local errors=0

    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js not found. Please install Node.js v18+ from https://nodejs.org/"
        errors=$((errors + 1))
    else
        local node_version=$(node -v | sed 's/v//' | cut -d'.' -f1)
        if [ "$node_version" -lt 18 ]; then
            error "Node.js v18+ required (found v$node_version)"
            errors=$((errors + 1))
        else
            success "Node.js v$node_version found"
        fi
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "Python 3 not found. Please install Python 3.9+ from https://python.org/"
        errors=$((errors + 1))
    else
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        local py_major=$(echo "$python_version" | cut -d'.' -f1)
        local py_minor=$(echo "$python_version" | cut -d'.' -f2)

        if [ "$py_major" -lt 3 ] || ([ "$py_major" -eq 3 ] && [ "$py_minor" -lt 9 ]); then
            error "Python 3.9+ required (found $python_version)"
            errors=$((errors + 1))
        else
            success "Python $python_version found"
        fi
    fi

    # Check pip
    if ! command -v pip3 &> /dev/null; then
        warning "pip3 not found - RAG dependencies will need manual installation"
        warning "Install with: python3 -m ensurepip --upgrade"
    else
        success "pip3 found"
    fi

    # Check Git
    if ! command -v git &> /dev/null; then
        error "Git not found. Please install Git from https://git-scm.com/"
        errors=$((errors + 1))
    else
        local git_version=$(git --version | cut -d' ' -f3 | cut -d'.' -f1,2)
        success "Git $git_version found"
    fi

    # Check ANTHROPIC_API_KEY
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        warning "ANTHROPIC_API_KEY not set. Hooks will not work until you set this."
        info "Set with: export ANTHROPIC_API_KEY='your-key-here'"
    else
        success "ANTHROPIC_API_KEY is set"
    fi

    if [ $errors -gt 0 ]; then
        error "\nPrerequisites check failed. Please install missing requirements."
        exit 1
    fi

    success "All prerequisites met!\n"
}

################################################################################
# Interactive Prompts
################################################################################

prompt_repo_url() {
    if [ "$SKIP_PROMPTS" = true ]; then
        if [ -z "$REPO_URL" ]; then
            error "Repository URL required when using --skip-prompts"
            exit 1
        fi
        return
    fi

    if [ -z "$REPO_URL" ]; then
        echo -e "\n${BOLD}Repository Configuration${NC}"
        read -p "Enter the autonomous system repository URL: " REPO_URL

        if [ -z "$REPO_URL" ]; then
            error "Repository URL is required"
            exit 1
        fi
    fi

    # Validate repository URL format
    if [[ ! "$REPO_URL" =~ ^(https?://|git@) ]]; then
        error "Invalid repository URL format: $REPO_URL"
        info "URL must start with http://, https://, or git@"
        exit 1
    fi

    echo -e "Using repository: ${GREEN}$REPO_URL${NC}"
}

prompt_configuration() {
    if [ "$SKIP_PROMPTS" = true ]; then
        return
    fi

    echo -e "\n${BOLD}Installation Configuration${NC}"
    echo "Choose configuration type:"
    echo "  1) Minimal (3 core hooks: SessionStart, UserPromptSubmit, PostToolUse)"
    echo "  2) Full (7+ hooks: includes learning extraction, design governance, etc.) [RECOMMENDED]"
    read -p "Enter choice [1-2] (default: 2): " config_choice

    case "$config_choice" in
        1) CONFIG_TYPE="minimal" ;;
        2|"") CONFIG_TYPE="full" ;;
        *)
            warning "Invalid choice. Using 'full' configuration."
            CONFIG_TYPE="full"
            ;;
    esac

    echo -e "Using configuration: ${GREEN}$CONFIG_TYPE${NC}"
}

################################################################################
# Installation Functions
################################################################################

check_git_repo() {
    step "Checking Git Repository"

    # Check if directory is a git repository
    if ! git rev-parse --git-dir &> /dev/null; then
        error "Not a git repository. Please run 'git init' first."
        exit 1
    fi

    # Check if repository has any commits (HEAD exists)
    if ! git rev-parse HEAD &> /dev/null; then
        warning "Git repository has no commits yet."
        info "Git subtree requires at least one commit to exist."

        if [ "$SKIP_PROMPTS" = false ]; then
            echo -e "\n${BOLD}Would you like to create an initial commit?${NC}"
            read -p "Create initial commit? [Y/n]: " create_commit
            if [[ ! "$create_commit" =~ ^[Nn]$ ]]; then
                # Create initial commit
                # Check if README.md already exists to avoid overwriting
                if [ ! -f "README.md" ]; then
                    echo "# $(basename "$PWD")" > README.md
                    git add README.md
                else
                    # README.md exists, add it if untracked
                    if ! git ls-files --error-unmatch README.md &> /dev/null; then
                        warning "README.md exists (untracked). Adding to git."
                        git add README.md
                    fi
                fi
                git commit -m "Initial commit" --quiet
                success "Initial commit created"
            else
                error "Cannot proceed without at least one commit."
                info "Run these commands first:"
                info "  echo '# My Project' > README.md"
                info "  git add README.md"
                info "  git commit -m 'Initial commit'"
                exit 1
            fi
        else
            # Non-interactive mode: create initial commit automatically
            # Check if README.md already exists to avoid overwriting
            if [ ! -f "README.md" ]; then
                echo "# $(basename "$PWD")" > README.md
                git add README.md
            else
                # README.md exists, add it if untracked
                if ! git ls-files --error-unmatch README.md &> /dev/null; then
                    info "README.md exists (untracked). Adding to git."
                    git add README.md
                fi
            fi
            git commit -m "Initial commit" --quiet
            success "Initial commit created automatically"
        fi
    fi

    # Check for uncommitted changes (now we know HEAD exists)
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warning "You have uncommitted changes. Consider committing before installation."

        if [ "$SKIP_PROMPTS" = false ]; then
            read -p "Continue anyway? [y/N]: " continue_choice
            if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                info "Installation cancelled"
                exit 0
            fi
        fi
    fi

    success "Git repository is ready"
}

add_git_subtree() {
    step "Adding Autonomous System as Git Subtree"

    # Check if remote already exists
    if git remote get-url lunigy-ai &> /dev/null; then
        info "Remote 'lunigy-ai' already exists"
    else
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would add remote: $REPO_URL"
        else
            git remote add lunigy-ai "$REPO_URL"
            CHANGES_MADE+=("added_remote")
            success "Added remote 'lunigy-ai'"
        fi
    fi

    # Check if .autonomous-system directory exists
    if [ -d ".autonomous-system" ]; then
        warning ".autonomous-system directory already exists"
        info "Skipping git subtree add (already added)"
    else
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would run: git subtree add --prefix=.autonomous-system lunigy-ai $BRANCH_NAME --squash"
        else
            info "This may take a minute..."
            git subtree add --prefix=.autonomous-system lunigy-ai "$BRANCH_NAME" --squash
            CHANGES_MADE+=("added_subtree")
            success "Git subtree added successfully"
        fi
    fi
}

create_directories() {
    step "Creating Claude Code Directory Structure"

    local dirs=(
        ".claude"
        ".claude/hooks"
        ".claude/commands"
        ".claude/agents"
        ".claude/skills"
    )

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            info "$dir already exists"
        else
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would create: $dir"
            else
                mkdir -p "$dir"
                CHANGES_MADE+=("created_dir:$dir")
                success "Created $dir"
            fi
        fi
    done
}

create_settings_json() {
    step "Creating settings.json Configuration"

    local settings_file=".claude/settings.json"

    # Backup if exists
    if [ -f "$settings_file" ]; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would backup existing settings.json"
        else
            local backup_file="${settings_file}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$settings_file" "$backup_file"
            warning "Existing settings.json backed up to: $backup_file"
            CHANGES_MADE+=("backed_up_settings")
        fi
    fi

    local settings_content
    if [ "$CONFIG_TYPE" = "minimal" ]; then
        settings_content=$(cat << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start-market-intelligence.py"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/user-prompt-validator.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write(*)|Edit(*)|MultiEdit(*)",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-tool-quality-check.sh"
          }
        ]
      }
    ]
  }
}
EOF
        )
    else
        settings_content=$(cat << 'EOF'
{
  "env": {
    "MAX_THINKING_TOKENS": "10000",
    "BASH_DEFAULT_TIMEOUT_MS": "60000",
    "BASH_MAX_TIMEOUT_MS": "300000"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start-market-intelligence.py"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/user-prompt-validator.py"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/feature-request-detector.py"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write(*)|Edit(*)",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-implementation-design-check.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write(*)|Edit(*)|MultiEdit(*)",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-tool-quality-check.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-end-learning-extraction.py"
          }
        ]
      }
    ]
  }
}
EOF
        )
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create settings.json with $CONFIG_TYPE configuration"
    else
        echo "$settings_content" > "$settings_file"
        CHANGES_MADE+=("created_settings")
        success "Created settings.json ($CONFIG_TYPE configuration)"
    fi
}

create_symlinks() {
    step "Creating Symlinks"

    # Auto-detect structure (nested vs. flat)
    local base_path
    if [ -d ".autonomous-system/.autonomous-system/hooks" ]; then
        # Nested structure (git subtree from project repo)
        base_path="../../.autonomous-system/.autonomous-system"
        info "Detected nested structure (project repo)"
    elif [ -d ".autonomous-system/hooks" ]; then
        # Flat structure (git subtree from autonomous-system-only repo)
        base_path="../../.autonomous-system"
        info "Detected flat structure (autonomous-system repo)"
    else
        error "Cannot find autonomous system hooks directory"
        return 1
    fi

    # Hooks symlinks
    local hooks=(
        "session-start-market-intelligence.py"
        "user-prompt-validator.py"
        "post-tool-quality-check.sh"
    )

    if [ "$CONFIG_TYPE" = "full" ]; then
        hooks+=(
            "session-end-learning-extraction.py"
            "feature-request-detector.py"
            "pre-implementation-design-check.py"
        )
    fi

    info "Creating hook symlinks..."
    for hook in "${hooks[@]}"; do
        local target="$base_path/hooks/$hook"
        local link=".claude/hooks/$hook"

        if [ -L "$link" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would replace existing symlink: $hook"
            else
                rm "$link"
                ln -s "$target" "$link"
                success "  $hook (replaced)"
            fi
        elif [ -e "$link" ]; then
            warning "  $hook exists as regular file (skipping)"
        else
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would create symlink: $hook"
            else
                ln -s "$target" "$link"
                CHANGES_MADE+=("created_symlink:$link")
                success "  $hook"
            fi
        fi
    done

    # Subagent files (direct copies, no symlinks needed)
    local subagents=(
        "discovery-mode.md"
        "engineering-mode.md"
        "launch-mode.md"
    )

    info "Creating agent files..."
    for subagent in "${subagents[@]}"; do
        local source="$base_path/claude-components/agents/$subagent"
        local dest=".claude/agents/$subagent"

        if [ ! -f "$source" ]; then
            warning "  Source not found: $source (skipping)"
            continue
        fi

        if [ -e "$dest" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would update: $subagent"
            else
                cp "$source" "$dest"
                success "  $subagent (updated)"
            fi
        else
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would create: $subagent"
            else
                cp "$source" "$dest"
                CHANGES_MADE+=("created_file:$dest")
                success "  $subagent"
            fi
        fi
    done

    # Note: Subagent slash commands (discovery.md, engineering.md, launch.md)
    # were deprecated and moved to agents. No longer needed.

    success "All agent files created"
}

verify_installation() {
    step "Verifying Installation"

    local errors=0

    # Check symlinks
    info "Checking hook symlinks..."
    for hook in .claude/hooks/*; do
        if [ -L "$hook" ]; then
            if [ -e "$hook" ]; then
                success "  $(basename "$hook") → OK"
            else
                error "  $(basename "$hook") → BROKEN"
                errors=$((errors + 1))
            fi
        fi
    done

    info "Checking agent files..."
    local agent_count=0
    for agent in .claude/agents/*.md; do
        if [ -e "$agent" ]; then
            success "  $(basename "$agent") → OK"
            agent_count=$((agent_count + 1))
        fi
    done
    if [ $agent_count -eq 0 ]; then
        warning "  No agent files found (this is OK for minimal setup)"
    fi

    # Note: Deprecated command files (discovery.md, engineering.md, launch.md)
    # are no longer checked as they were moved to agents

    # Validate JSON
    info "Validating settings.json..."
    if python3 -m json.tool .claude/settings.json > /dev/null 2>&1; then
        success "  settings.json is valid JSON"
    else
        error "  settings.json has invalid JSON syntax"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        error "\nVerification found $errors error(s)"
        return 1
    fi

    success "\nAll verification checks passed! ✨"
    return 0
}

################################################################################
# RAG System Setup
################################################################################

install_rag_dependencies() {
    if [ "$INSTALL_RAG" = false ]; then
        info "Skipping RAG dependencies (--skip-rag specified)"
        return 0
    fi

    step "Installing RAG System Dependencies"

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would install: sentence-transformers, faiss-cpu, numpy"
        return 0
    fi

    # Check if requirements.txt exists
    local req_file=".autonomous-system/orchestration/requirements.txt"
    if [ ! -f "$req_file" ]; then
        warning "Requirements file not found: $req_file"
        warning "RAG dependencies will need manual installation"
        return 0
    fi

    info "Installing Python dependencies (this may take 2-3 minutes)..."

    # Install in user space to avoid permission issues
    if python3 -m pip install --user -r "$req_file" --quiet; then
        success "RAG dependencies installed successfully"
        CHANGES_MADE+=("installed_rag_deps")
    else
        warning "Failed to install RAG dependencies automatically"
        warning "Install manually: pip install -r $req_file"
    fi
}

setup_rag_hooks() {
    if [ "$SETUP_RAG_HOOKS" = false ]; then
        info "Skipping RAG git hooks (use --rag-hooks to enable)"
        return 0
    fi

    step "Setting Up RAG Auto-Indexing Git Hooks"

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would install RAG git hooks"
        return 0
    fi

    local hook_installer=".autonomous-system/scripts/install-rag-hooks.sh"
    if [ ! -f "$hook_installer" ]; then
        warning "RAG hook installer not found: $hook_installer"
        return 0
    fi

    if bash "$hook_installer"; then
        success "RAG git hooks installed"
        CHANGES_MADE+=("installed_rag_hooks")
    else
        warning "Failed to install RAG git hooks"
        warning "Install manually: bash $hook_installer"
    fi
}

run_initial_rag_index() {
    if [ "$RUN_RAG_INDEX" = false ]; then
        info "Skipping initial RAG indexing (use --rag-index to enable)"
        return 0
    fi

    step "Running Initial RAG Index"

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would run initial RAG indexing"
        return 0
    fi

    local rag_cli=".autonomous-system/scripts/rag-cli.py"
    if [ ! -f "$rag_cli" ]; then
        warning "RAG CLI not found: $rag_cli"
        return 0
    fi

    info "Indexing codebase (this may take 2-5 minutes for first run)..."

    if python3 "$rag_cli" index; then
        success "RAG index created successfully"
        CHANGES_MADE+=("created_rag_index")
    else
        warning "Failed to create RAG index"
        warning "Run manually: python3 $rag_cli index"
    fi
}

################################################################################
# Cleanup and Rollback
################################################################################

cleanup_on_failure() {
    error "\n\nInstallation failed! Rolling back changes..."

    for change in "${CHANGES_MADE[@]}"; do
        case "$change" in
            added_remote)
                info "Removing remote 'lunigy-ai'..."
                git remote remove lunigy-ai 2>/dev/null || true
                ;;
            added_subtree)
                info "Removing .autonomous-system directory..."
                rm -rf .autonomous-system 2>/dev/null || true
                ;;
            created_dir:*)
                local dir="${change#created_dir:}"
                info "Removing $dir..."
                rmdir "$dir" 2>/dev/null || true
                ;;
            created_settings)
                info "Removing settings.json..."
                rm -f .claude/settings.json 2>/dev/null || true
                # Restore backup if exists
                local backup=$(ls -t .claude/settings.json.backup.* 2>/dev/null | head -1)
                if [ -n "$backup" ]; then
                    mv "$backup" .claude/settings.json
                    info "Restored backup: $backup"
                fi
                ;;
            created_symlink:*)
                local link="${change#created_symlink:}"
                info "Removing symlink: $link..."
                rm -f "$link" 2>/dev/null || true
                ;;
            installed_rag_deps)
                info "RAG dependencies were installed but may need manual cleanup"
                ;;
            installed_rag_hooks)
                info "Removing RAG git hooks..."
                rm -f .git/hooks/post-commit 2>/dev/null || true
                rm -f .git/hooks/pre-push 2>/dev/null || true
                ;;
            created_rag_index)
                info "Removing RAG index..."
                rm -rf .autonomous-system/.rag-cache 2>/dev/null || true
                ;;
        esac
    done

    error "\n✅ Rollback complete"
    exit 1
}

trap cleanup_on_failure ERR

################################################################################
# Main Installation Flow
################################################################################

show_summary() {
    echo -e "\n${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║             🎉 Installation Successful! 🎉                     ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝${NC}"

    echo -e "\n${BOLD}What was installed:${NC}"
    echo "  ✅ Autonomous system ($CONFIG_TYPE configuration)"
    echo "  ✅ Claude Code directory structure"
    echo "  ✅ settings.json configuration"
    echo "  ✅ Hook symlinks ($([ "$CONFIG_TYPE" = "minimal" ] && echo "3" || echo "6") hooks)"
    echo "  ✅ Agent files (3 modes: Discovery, Engineering, Launch)"

    # Add RAG status
    if [ "$INSTALL_RAG" = true ]; then
        echo "  ✅ RAG system dependencies"
    fi
    if [ "$SETUP_RAG_HOOKS" = true ]; then
        echo "  ✅ RAG auto-indexing git hooks"
    fi
    if [ "$RUN_RAG_INDEX" = true ]; then
        echo "  ✅ RAG codebase index"
    fi

    echo -e "\n${BOLD}Next Steps:${NC}"
    echo "  1. Open Claude Code in this directory"

    # If RAG was installed, add RAG-specific instructions
    if [ "$INSTALL_RAG" = true ]; then
        echo "  2. Enable RAG automatic context loading:"
        echo "     Add to .claude/settings.json PreToolUse hook:"
        echo "     ${BLUE}\$CLAUDE_PROJECT_DIR/.autonomous-system/hooks/pre-tool-use-rag-context.py${NC}"
        echo ""
        if [ "$RUN_RAG_INDEX" = false ]; then
            echo "  3. Index your codebase (first time):"
            echo "     ${BLUE}python3 .autonomous-system/scripts/rag-cli.py index${NC}"
            echo ""
        fi
    fi

    echo "  4. Test the regulatory validator:"
    echo "     ${BLUE}Say: \"Let's build a medical credentialing platform\"${NC}"
    echo "     ${GREEN}Expected: 🚨 CRITICAL REGULATORY ALERT${NC}"
    echo ""
    echo "  3. Try the specialized subagents:"
    echo "     ${BLUE}/discovery${NC}     - Market research & opportunity validation"
    echo "     ${BLUE}/engineering${NC}   - High-velocity, high-quality development"
    echo "     ${BLUE}/launch${NC}        - Revenue-focused growth & marketing"

    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo -e "\n${YELLOW}⚠️  Remember to set ANTHROPIC_API_KEY:${NC}"
        echo "     ${BLUE}export ANTHROPIC_API_KEY='your-key-here'${NC}"
    fi

    echo -e "\n${BOLD}Documentation:${NC}"
    echo "  📖 Full guide: .autonomous-system/docs/INSTALLATION-GUIDE.md"
    echo "  🐛 Troubleshooting: .autonomous-system/docs/INSTALLATION-GUIDE.md#troubleshooting"
    echo "  🏗️  Architecture: .autonomous-system/README.md"

    echo -e "\n${GREEN}Happy building! 🚀${NC}\n"
}

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config=*)
                CONFIG_TYPE="${1#*=}"
                shift
                ;;
            --config)
                CONFIG_TYPE="$2"
                shift 2
                ;;
            --repo-url=*)
                REPO_URL="${1#*=}"
                shift
                ;;
            --repo-url)
                REPO_URL="$2"
                shift 2
                ;;
            --branch=*)
                BRANCH_NAME="${1#*=}"
                shift
                ;;
            --branch)
                BRANCH_NAME="$2"
                shift 2
                ;;
            --skip-prompts)
                SKIP_PROMPTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-rag)
                INSTALL_RAG=false
                shift
                ;;
            --rag-hooks)
                SETUP_RAG_HOOKS=true
                shift
                ;;
            --rag-index)
                RUN_RAG_INDEX=true
                shift
                ;;
            --help)
                show_help
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Show header
    print_header

    if [ "$DRY_RUN" = true ]; then
        warning "DRY RUN MODE - No changes will be made\n"
    fi

    # Run installation steps
    check_prerequisites
    prompt_repo_url
    prompt_configuration
    check_git_repo
    add_git_subtree
    create_directories
    create_settings_json
    create_symlinks
    install_rag_dependencies
    setup_rag_hooks
    run_initial_rag_index

    if [ "$DRY_RUN" = false ]; then
        verify_installation
        show_summary
    else
        info "\n[DRY RUN] Installation simulation complete. No changes were made."
        info "Run without --dry-run to perform actual installation."
    fi
}

# Run main function
main "$@"
