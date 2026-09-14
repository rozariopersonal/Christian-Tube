#!/usr/bin/env bash
set -e

ACTION="${1:-list}"
NAME="$2"
BASE="${3:-develop}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREES_DIR="$ROOT_DIR/.worktrees"

normalize_name() {
  local input="$1"
  if [ -z "$input" ]; then
    echo "Error: Task name is required."
    exit 1
  fi
  echo "$input" | sed -e 's/^agent\///' -e 's/[ _]/-/g' | tr '[:upper:]' '[:lower:]'
}

case "$ACTION" in
  list)
    echo "=== Active Git Worktrees ==="
    git worktree list
    ;;

  prune)
    echo "Pruning stale worktrees..."
    git worktree prune
    echo "Done."
    ;;

  create)
    TASK_NAME=$(normalize_name "$NAME")
    BRANCH_NAME="agent/$TASK_NAME"
    TARGET_DIR="$WORKTREES_DIR/$TASK_NAME"

    if [ -d "$TARGET_DIR" ]; then
      echo "Warning: Worktree directory already exists at: $TARGET_DIR"
      echo "cd $TARGET_DIR"
      exit 0
    fi

    echo "🚀 Creating isolated worktree for agent task: $TASK_NAME"
    mkdir -p "$WORKTREES_DIR"

    echo "[1/3] Fetching latest origin/$BASE..."
    git fetch origin "$BASE"

    START_POINT="origin/$BASE"
    if ! git rev-parse --verify "origin/$BASE" > /dev/null 2>&1; then
      START_POINT="$BASE"
    fi

    echo "[2/3] Adding git worktree..."
    if git rev-parse --verify "refs/heads/$BRANCH_NAME" > /dev/null 2>&1; then
      git worktree add "$TARGET_DIR" "$BRANCH_NAME"
    else
      git worktree add -b "$BRANCH_NAME" "$TARGET_DIR" "$START_POINT"
    fi

    echo "[3/3] Bootstrapping submodules & dependencies..."
    cd "$TARGET_DIR"
    git submodule update --init --recursive releases

    if [ -d "$TARGET_DIR/apps/mobile" ]; then
      cd "$TARGET_DIR/apps/mobile"
      flutter pub get
    fi

    echo ""
    echo "🎉 Worktree ready! Navigate to:"
    echo "cd $TARGET_DIR"
    ;;

  remove)
    TASK_NAME=$(normalize_name "$NAME")
    BRANCH_NAME="agent/$TASK_NAME"
    TARGET_DIR="$WORKTREES_DIR/$TASK_NAME"

    echo "Cleaning up worktree: $TASK_NAME..."
    if [ -d "$TARGET_DIR" ]; then
      git worktree remove "$TARGET_DIR" --force
    else
      git worktree prune
    fi

    if git rev-parse --verify "refs/heads/$BRANCH_NAME" > /dev/null 2>&1; then
      git branch -D "$BRANCH_NAME" || true
      echo "Deleted branch: $BRANCH_NAME"
    fi

    echo "✅ Worktree cleanup complete."
    ;;

  *)
    echo "Usage: ./scripts/worktree.sh [create|remove|list|prune] [task-name] [base-branch]"
    exit 1
    ;;
esac
