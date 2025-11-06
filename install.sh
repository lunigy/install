#!/usr/bin/env bash

################################################################################
# Lunigy AI Autonomous System - Installation Script
#
# Version: 1.0.0
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
SCRIPT_VERSION="1.0.0"
CONFIG_TYPE="full"
REPO_URL=""
BRANCH_NAME="main"
SKIP_PROMPTS=false
DRY_RUN=false
INSTALL_RAG=true           # Install RAG dependencies
SETUP_RAG_HOOKS=false      # Install RAG git hooks
RUN_RAG_INDEX=false        # Run initial RAG indexing
SETUP_DASHBOARD=true       # Setup health dashboard
SKIP_DASHBOARD=false       # Skip dashboard installation
START_DASHBOARD=true       # Start dashboard after installation
DASHBOARD_PORT=3000        # Dashboard port

# State tracking
BACKUP_DIR=""
CHANGES_MADE=()
DASHBOARD_PID=""

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

    RAG System:
    --skip-rag              Skip RAG system installation (not recommended)
    --rag-hooks             Install RAG auto-indexing git hooks
    --rag-index             Run initial RAG index after installation

    Health Dashboard:
    --skip-dashboard        Skip health dashboard installation
    --no-start-dashboard    Install dashboard but don't start server
    --dashboard-port <port> Dashboard port (default: 3000)

    --help                  Show this help message

EXAMPLES:
    # Interactive installation (recommended - includes dashboard)
    bash install.sh --repo-url=git@github.com:lunigy/ai-autonomous-system-system.git

    # Full installation with RAG and dashboard auto-start
    bash install.sh --repo-url=<url> --config=full --rag-hooks --rag-index

    # Minimal installation without dashboard (headless/CI mode)
    bash install.sh --repo-url=<url> --config=minimal --skip-dashboard --skip-prompts

    # Custom dashboard port
    bash install.sh --repo-url=<url> --dashboard-port=8080

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
        ".claude/agents"
        ".claude/commands"
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
        "matcher": "*",
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
        "matcher": "*",
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
        "matcher": "Write|Edit|MultiEdit",
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
        "matcher": "*",
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
        "matcher": "*",
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
        "matcher": "Write|Edit",
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
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-tool-quality-check.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/subagent-stop-metrics.py",
            "description": "Track subagent performance metrics"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/subagent-stop-learning.py",
            "description": "Extract learnings from subagent execution"
          },
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/subagent-stop-validator.py",
            "description": "Validate subagent output quality"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
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
    local source_path
    if [ -d ".autonomous-system/.autonomous-system/hooks" ]; then
        # Nested structure (git subtree from project repo)
        base_path="../../.autonomous-system/.autonomous-system"
        source_path=".autonomous-system/.autonomous-system"
        info "Detected nested structure (project repo)"
    elif [ -d ".autonomous-system/hooks" ]; then
        # Flat structure (git subtree from autonomous-system-only repo)
        base_path="../../.autonomous-system"
        source_path=".autonomous-system"
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
            "subagent-stop-metrics.py"
            "subagent-stop-learning.py"
            "subagent-stop-validator.py"
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
    # Dynamically discover all available subagent files (including subdirectories)
    info "Discovering available subagent files..."

    # Copy all .md files recursively from agents directory
    local subagent_count=0
    if [ -d "$source_path/claude-components/agents" ]; then
        while IFS= read -r -d '' source_file; do
            # Get relative path from agents directory
            local rel_path="${source_file#$source_path/claude-components/agents/}"
            local dest_file=".claude/agents/$rel_path"
            local dest_dir="$(dirname "$dest_file")"

            # Create destination directory if needed
            if [ ! -d "$dest_dir" ]; then
                mkdir -p "$dest_dir"
            fi

            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would copy: $rel_path"
            else
                cp "$source_file" "$dest_file"
                CHANGES_MADE+=("created_file:$dest_file")
                subagent_count=$((subagent_count + 1))
            fi
        done < <(find "$source_path/claude-components/agents" -name "*.md" -type f -print0 2>/dev/null)

        success "Installed $subagent_count subagent files"
    else
        warning "Agents directory not found: $source_path/claude-components/agents"
    fi

    # Slash commands (dynamically discover all available)
    info "Discovering available command files..."

    # Copy all .md files recursively from commands directory (including templates)
    local command_count=0
    if [ -d "$source_path/claude-components/commands" ]; then
        while IFS= read -r -d '' source_file; do
            # Get relative path from commands directory
            local rel_path="${source_file#$source_path/claude-components/commands/}"
            local dest_file=".claude/commands/$rel_path"
            local dest_dir="$(dirname "$dest_file")"

            # Create destination directory if needed
            if [ ! -d "$dest_dir" ]; then
                mkdir -p "$dest_dir"
            fi

            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would copy: $rel_path"
            else
                cp "$source_file" "$dest_file"
                CHANGES_MADE+=("created_file:$dest_file")
                command_count=$((command_count + 1))
            fi
        done < <(find "$source_path/claude-components/commands" -name "*.md" -type f -print0 2>/dev/null)

        success "Installed $command_count command files"
    else
        warning "Commands directory not found: $source_path/claude-components/commands"
    fi

    # Skills (dynamically discover all available)
    info "Discovering available skill files..."
    info "[DEBUG] Source path: $source_path"
    info "[DEBUG] Skills directory: $source_path/claude-components/skills"
    info "[DEBUG] DRY_RUN=$DRY_RUN"

    # Copy all skill directories recursively from skills directory
    local skill_count=0
    if [ -d "$source_path/claude-components/skills" ]; then
        info "[DEBUG] Skills directory exists"

        # Debug: Count available skills
        local available_skills=$(find "$source_path/claude-components/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        info "[DEBUG] Available skills in source: $available_skills"

        while IFS= read -r -d '' source_dir; do
            # Get skill name (directory name)
            local skill_name="$(basename "$source_dir")"
            local dest_dir=".claude/skills/$skill_name"

            info "[DEBUG] Processing skill: $skill_name"
            info "[DEBUG]   Source: $source_dir"
            info "[DEBUG]   Dest: $dest_dir"

            # Create destination directory if needed
            if [ ! -d "$dest_dir" ]; then
                mkdir -p "$dest_dir"
                info "[DEBUG]   Created dest directory"
            fi

            # Copy all files from skill directory
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would copy skill: $skill_name"
            else
                info "[DEBUG]   Copying files..."
                if cp -r "$source_dir/"* "$dest_dir/" 2>&1; then
                    CHANGES_MADE+=("created_skill:$dest_dir")
                    skill_count=$((skill_count + 1))
                    success "  ✓ $skill_name"
                else
                    error "  ✗ Failed to copy: $skill_name"
                fi
            fi
        done < <(find "$source_path/claude-components/skills" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        info "[DEBUG] Loop completed. Skills copied: $skill_count"
        success "Installed $skill_count skill directories"
    else
        warning "Skills directory not found: $source_path/claude-components/skills"
    fi

    success "All subagents, commands, and skills created"
}

create_claude_md() {
    step "Creating CLAUDE.md Configuration"

    local template_path
    if [ -d ".autonomous-system/.autonomous-system/templates" ]; then
        template_path=".autonomous-system/.autonomous-system/templates/CLAUDE.md.template"
    else
        template_path=".autonomous-system/templates/CLAUDE.md.template"
    fi

    if [ ! -f "$template_path" ]; then
        warning "CLAUDE.md template not found at: $template_path"
        info "Skipping CLAUDE.md creation"
        return 0
    fi

    if [ -f "CLAUDE.md" ]; then
        warning "CLAUDE.md already exists"
        if [ "$DRY_RUN" = false ]; then
            local backup="CLAUDE.md.backup.$(date +%Y%m%d_%H%M%S)"
            mv CLAUDE.md "$backup"
            CHANGES_MADE+=("backed_up:CLAUDE.md:$backup")
            info "Existing CLAUDE.md backed up to: $backup"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create CLAUDE.md from template"
    else
        cp "$template_path" CLAUDE.md
        CHANGES_MADE+=("created_file:CLAUDE.md")
        success "Created CLAUDE.md at project root"
        info "This file is automatically loaded by Claude Code at session start"
    fi
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

    info "Checking subagent files..."
    for subagent in .claude/agents/*.md; do
        if [ -e "$subagent" ]; then
            success "  $(basename "$subagent") → OK"
        else
            error "  $(basename "$subagent") → MISSING"
            errors=$((errors + 1))
        fi
    done

    info "Checking subagent commands..."
    for cmd in .claude/commands/discovery.md .claude/commands/engineering.md .claude/commands/launch.md; do
        if [ -e "$cmd" ]; then
            success "  $(basename "$cmd") → OK"
        else
            error "  $(basename "$cmd") → MISSING"
            errors=$((errors + 1))
        fi
    done

    # Validate JSON
    info "Validating settings.json..."
    if python3 -m json.tool .claude/settings.json > /dev/null 2>&1; then
        success "  settings.json is valid JSON"
    else
        error "  settings.json has invalid JSON syntax"
        errors=$((errors + 1))
    fi

    # Check CLAUDE.md
    info "Checking CLAUDE.md..."
    if [ -f "CLAUDE.md" ]; then
        success "  CLAUDE.md exists at project root"
        info "  This file is automatically loaded by Claude Code"
    else
        warning "  CLAUDE.md not found (recommended for Claude Code)"
        info "  Create manually from: .autonomous-system/templates/CLAUDE.md.template"
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
# Dashboard Setup
################################################################################

setup_dashboard() {
    if [ "$SKIP_DASHBOARD" = true ]; then
        info "Skipping dashboard setup (--skip-dashboard specified)"
        return 0
    fi

    step "Setting Up Health Dashboard"

    # Check if dashboard template exists
    local template_dir
    if [ -d ".autonomous-system/templates/dashboard" ]; then
        template_dir=".autonomous-system/templates/dashboard"
    elif [ -d ".autonomous-system/.autonomous-system/templates/dashboard" ]; then
        template_dir=".autonomous-system/.autonomous-system/templates/dashboard"
    else
        warning "Dashboard template not found - skipping"
        info "Dashboard can be set up later with: bash .autonomous-system/scripts/initialize-dashboard.sh"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would initialize dashboard from template"
        return 0
    fi

    # Get project name
    local project_name=$(basename "$PWD")
    local project_id=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

    info "Initializing dashboard for project: $project_name"

    # Check if initialize-dashboard.sh exists
    local init_script
    if [ -f ".autonomous-system/scripts/initialize-dashboard.sh" ]; then
        init_script=".autonomous-system/scripts/initialize-dashboard.sh"
    elif [ -f ".autonomous-system/.autonomous-system/scripts/initialize-dashboard.sh" ]; then
        init_script=".autonomous-system/.autonomous-system/scripts/initialize-dashboard.sh"
    else
        warning "Dashboard initialization script not found"
        info "You can copy the dashboard template manually: cp -r $template_dir apps/dashboard"
        return 0
    fi

    # Run initialization script
    if bash "$init_script" "$project_name" "$project_id"; then
        success "Dashboard initialized at apps/dashboard/"
        CHANGES_MADE+=("initialized_dashboard")

        # Install dependencies
        if [ -d "apps/dashboard" ]; then
            info "Installing dashboard dependencies (this may take 30-60 seconds)..."
            cd apps/dashboard

            if npm install --silent 2>/dev/null; then
                success "Dashboard dependencies installed"
                CHANGES_MADE+=("installed_dashboard_deps")

                # Start dashboard if requested
                if [ "$START_DASHBOARD" = true ]; then
                    start_dashboard_server
                fi
            else
                warning "Dashboard dependencies installation failed"
                warning "Install manually: cd apps/dashboard && npm install"
            fi

            cd ../..
        fi
    else
        warning "Dashboard initialization failed"
        warning "You can initialize manually: bash $init_script \"$project_name\" \"$project_id\""
    fi
}

start_dashboard_server() {
    info "Starting dashboard server..."

    # Start in background
    npm run dev > .dashboard.log 2>&1 &
    local pid=$!
    echo "$pid" > .dashboard.pid
    DASHBOARD_PID="$pid"

    # Wait for server to start (max 10 seconds)
    local max_attempts=20
    local attempt=0
    local server_ready=false

    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:$DASHBOARD_PORT" > /dev/null 2>&1; then
            server_ready=true
            break
        fi
        sleep 0.5
        ((attempt++))
    done

    if [ "$server_ready" = true ]; then
        success "Dashboard running at http://localhost:$DASHBOARD_PORT"
        CHANGES_MADE+=("started_dashboard")
    else
        warning "Dashboard server may not be ready yet"
        info "Check status: curl http://localhost:$DASHBOARD_PORT"
        info "View logs: tail -f apps/dashboard/.dashboard.log"
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
            created_file:CLAUDE.md)
                info "Removing CLAUDE.md..."
                rm -f CLAUDE.md 2>/dev/null || true
                ;;
            backed_up:CLAUDE.md:*)
                local backup="${change#backed_up:CLAUDE.md:}"
                info "Restoring CLAUDE.md from backup..."
                if [ -f "$backup" ]; then
                    mv "$backup" CLAUDE.md
                    info "Restored: $backup"
                fi
                ;;
            created_file:*)
                local file="${change#created_file:}"
                info "Removing file: $file..."
                rm -f "$file" 2>/dev/null || true
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
            initialized_dashboard)
                info "Removing dashboard directory..."
                rm -rf apps/dashboard 2>/dev/null || true
                ;;
            installed_dashboard_deps)
                info "Dashboard dependencies were installed (in apps/dashboard/node_modules)"
                ;;
            started_dashboard)
                info "Stopping dashboard server..."
                if [ -f "apps/dashboard/.dashboard.pid" ]; then
                    local pid=$(cat apps/dashboard/.dashboard.pid)
                    kill "$pid" 2>/dev/null || true
                    rm -f apps/dashboard/.dashboard.pid
                fi
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
    echo "  ✅ Hook symlinks ($([ "$CONFIG_TYPE" = "minimal" ] && echo "3" || echo "9") hooks)"
    echo "  ✅ Subagents (3 modes: Discovery, Engineering, Launch)"
    echo "  ✅ Subagent slash commands"

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

    # Add Dashboard status
    if [ "$SKIP_DASHBOARD" = false ] && [ -d "apps/dashboard" ]; then
        echo "  ✅ Health dashboard initialized"
        if [ -d "apps/dashboard/node_modules" ]; then
            echo "  ✅ Dashboard dependencies installed"
        fi
        if [ -n "$DASHBOARD_PID" ]; then
            echo "  ✅ Dashboard running at http://localhost:$DASHBOARD_PORT"
        fi
    fi

    # Dashboard URL section if running
    if [ -n "$DASHBOARD_PID" ] || ([ -f "apps/dashboard/.dashboard.pid" ] && kill -0 $(cat apps/dashboard/.dashboard.pid) 2>/dev/null); then
        echo ""
        echo -e "${BOLD}${GREEN}🎯 Your Health Dashboard:${NC}"
        echo "  📊 View at: ${GREEN}http://localhost:$DASHBOARD_PORT${NC}"
        echo "  📈 Sprint progress tracked automatically"
        echo "  📝 User stories visible in real-time"
        echo "  🧠 Learnings displayed as they're captured"
        echo "  🚨 Regulatory alerts shown with context"
        echo ""
        echo "  ${BLUE}Tip:${NC} Keep this tab open to monitor your autonomous system!"
    fi

    echo -e "\n${BOLD}Next Steps:${NC}"

    # Configuration needed?
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        echo -e "\n${YELLOW}⚠️  REQUIRED: Configure API Credentials${NC}"
        echo "     Get your key from: https://console.anthropic.com/settings/keys"
        echo "     Set with: ${BLUE}export ANTHROPIC_API_KEY='your-key-here'${NC}"
        echo "     Add to ~/.bashrc or ~/.zshrc to persist"
        echo ""
    fi

    echo "  1. Verify system is ready:"
    echo "     ${BLUE}bash .autonomous-system/scripts/validate-system.sh${NC}"
    echo ""
    echo "  2. Open Claude Code in this directory"
    echo ""
    echo "  3. Test the regulatory validator:"
    echo "     ${BLUE}Say: \"Let's build a medical credentialing platform\"${NC}"
    echo "     ${GREEN}Expected: 🚨 CRITICAL REGULATORY ALERT${NC}"
    echo ""
    echo "  4. Try the specialized subagents:"
    echo "     ${BLUE}/discovery${NC}     - Market research & opportunity validation"
    echo "     ${BLUE}/engineering${NC}   - High-velocity, high-quality development"
    echo "     ${BLUE}/launch${NC}        - Revenue-focused growth & marketing"

    # If RAG was installed, add RAG-specific instructions
    if [ "$INSTALL_RAG" = true ]; then
        echo ""
        echo "  5. Enable RAG automatic context loading (optional):"
        echo "     Add to .claude/settings.json PreToolUse hook:"
        echo "     ${BLUE}\$CLAUDE_PROJECT_DIR/.autonomous-system/hooks/pre-tool-use-rag-context.py${NC}"
        echo ""
        if [ "$RUN_RAG_INDEX" = false ]; then
            echo "  6. Index your codebase for RAG (first time):"
            echo "     ${BLUE}python3 .autonomous-system/scripts/rag-cli.py index${NC}"
            echo ""
        fi
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
            --skip-dashboard)
                SKIP_DASHBOARD=true
                shift
                ;;
            --no-start-dashboard)
                START_DASHBOARD=false
                shift
                ;;
            --dashboard-port=*)
                DASHBOARD_PORT="${1#*=}"
                shift
                ;;
            --dashboard-port)
                DASHBOARD_PORT="$2"
                shift 2
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
    create_claude_md
    install_rag_dependencies
    setup_rag_hooks
    run_initial_rag_index
    setup_dashboard

    if [ "$DRY_RUN" = false ]; then
        verify_installation || {
            error "Installation verification failed"
            exit 1
        }

        # Run system validation
        if [ -f ".autonomous-system/scripts/validate-system.sh" ]; then
            echo ""
            info "Running system validation..."
            if bash .autonomous-system/scripts/validate-system.sh; then
                success "System validation passed!"
            else
                warning "System validation completed with warnings or errors"
                warning "Review the output above and fix any critical issues"
                echo ""
                echo "You can re-run validation anytime with:"
                echo "  bash .autonomous-system/scripts/validate-system.sh"
            fi
        fi

        show_summary
    else
        info "\n[DRY RUN] Installation simulation complete. No changes were made."
        info "Run without --dry-run to perform actual installation."
    fi
}

# Run main function
main "$@"
