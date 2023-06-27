#!/bin/bash

# Fail immediately if there is an error thrown
set -e

TEST_DIR=$(dirname "$(dirname "$(cd "$(dirname "$0")" || exit 1; pwd)/$(basename "$0")")")
SCRIPTS_DIR="$TEST_DIR/../scripts"
DUMMY_DIR="$HOME/DumDumRepo"
REPO_URL="https://github.com/roryabraham/DumDumRepo"
getPullRequestsMergedBetween="$TEST_DIR/utils/getPullRequestsMergedBetween.mjs"
INITIAL_COMMIT_HASH="5558c22349548c00bd7bc93914904469ff7cdedc"

source "$SCRIPTS_DIR/shellUtils.sh"

function setup_git_authorization {
  if [[ -n "$(git remote -v)" ]]; then
    git remote remove origin
  fi
  git remote add origin "https://$GITHUB_TOKEN@github.com/roryabraham/DumDumRepo"
}

function setup_git_as_human {
  info "Switching to human git user"
  git config --local user.name test
  git config --local user.email test@test.com
}

function setup_git_as_osbotify {
  info "Switching to OSBotify git user"
  git config --local user.name OSBotify
  git config --local user.email infra+osbotify@expensify.com
}

function remove_repo_if_needed {
  if [ -d "$DUMMY_DIR" ]; then
    info "Found existing directory at $DUMMY_DIR, deleting it..."
    cd "$HOME" || exit 1
    rm -rf "$DUMMY_DIR"
  fi
}

function reset_repo_to_initial_state {
  info "Resetting remote repo to initial state..."
  remove_repo_if_needed
  cd "$HOME" || exit 1
  git clone "$REPO_URL"
  cd "$DUMMY_DIR" || exit 1
  setup_git_authorization
  setup_git_as_osbotify
  git reset --hard "$INITIAL_COMMIT_HASH"
  git push --force origin main

  # Delete all branches except main
  git branch -r | grep 'origin' | grep -v 'main$' | grep -v HEAD | cut -d/ -f2- | while read -r line; do git push --force origin ":heads/$line"; done;

  # Delete all tags
  # shellcheck disable=SC2046
  git push origin --delete $(git tag --list)

  if git rev-parse --verify staging; then
    git branch -D staging
  fi
  git branch staging
  git push --force origin staging

  if git rev-parse --verify production; then
    git branch -D production
  fi
  git branch production
  git push --force origin production

  cd "$HOME" || exit 1
  rm -rf "$DUMMY_DIR"
  success "Reset remote repo to initial state!"
}

# Note that instead of doing a git clone, we checkout the repo following the same steps used by actions/checkout
function checkout_repo {
  info "Checking out repo at $DUMMY_DIR"
  remove_repo_if_needed
  mkdir "$DUMMY_DIR"
  cd "$DUMMY_DIR" || exit 1
  git init
  setup_git_authorization
  setup_git_as_osbotify
  git fetch --no-tags --prune --progress --no-recurse-submodules --depth=1 origin +refs/heads/main:refs/remotes/origin/main
  git checkout --progress --force -B main refs/remotes/origin/main
  success "Checked out repo at $DUMMY_DIR!"
}

function print_version {
  < package.json jq -r .version
}

function bump_version {
  info "Bumping version..."
  setup_git_as_osbotify
  git switch main
  if [[ $1 == 'minor' ]]; then
    npm --no-git-tag-version version minor
  else
    npm --no-git-tag-version version patch
  fi
  git add package.json package-lock.json
  git commit -m "Update version to $(print_version)"
  git push origin main
  success "Version bumped to $(print_version) on main"
}

function update_staging_from_main {
  info "Recreating staging from main..."
  git switch main
  if ! git rev-parse --verify staging; then
    git fetch origin staging --depth=1
  fi
  git branch -D staging
  git switch -c staging
  git push --force origin staging
  success "Recreated staging from main!"
}

function update_production_from_staging {
  info "Recreating production from staging..."
  if ! git rev-parse --verify staging; then
    git fetch origin staging --depth=1
  fi

  git switch staging
  if ! git rev-parse --verify production; then
    git fetch origin production --depth=1
  fi
  git branch -D production
  git switch -c production
  git push --force origin production
  success "Recreated production from staging!"
}

function merge_pr {
  info "Merging PR #$1 to main"
  git switch main
  git merge "pr-$1" --no-ff -m "Merge pull request #$1 from Expensify/pr-$1"
  git push origin main
  git branch -d "pr-$1"
  success "Merged PR #$1 to main"
}

function cherry_pick_pr {
  info "Cherry-picking PR $1 to staging..."
  merge_pr "$1"
  PR_MERGE_COMMIT="$(git rev-parse HEAD)"

  bump_version patch
  VERSION_BUMP_COMMIT="$(git rev-parse HEAD)"

  if ! git rev-parse --verify staging; then
    git fetch origin staging --depth=1
  fi

  git switch staging
  git switch -c cherry-pick-staging
  git cherry-pick -x --mainline 1 --strategy=recursive -Xtheirs "$PR_MERGE_COMMIT"
  git cherry-pick -x --mainline 1 "$VERSION_BUMP_COMMIT"

  git switch staging
  # TODO: test CPs with and without a PR involved
  git merge cherry-pick-staging --no-ff -m "Merge pull request #$(($1 + 1)) from Expensify/cherry-pick-staging"
  git branch -d cherry-pick-staging
  git push origin staging
  info "Merged PR #$(($1 + 1)) into staging"

  success "Successfully cherry-picked PR #$1 to staging!"
}

function tag_staging {
  info "Tagging new version from the staging branch..."
  setup_git_as_osbotify
  git switch staging
  git tag "$(print_version)"
  git push --tags
  success "Created new tag $(print_version)"
}

function assert_prs_merged_between {
  info "Checking output of getPullRequestsMergedBetween $1 $2"
  checkout_repo
  output=$(node "$getPullRequestsMergedBetween" "$1" "$2")
  assert_equal "$output" "$3"
}

### Phase 0: Verify necessary tools are installed (all tools should be pre-installed on all GitHub Actions runners)

if ! command -v jq &> /dev/null; then
  error "command jq could not be found, install it with \`brew install jq\` (macOS) or \`apt-get install jq\` (Linux) and re-run this script"
  exit 1
fi

if ! command -v npm &> /dev/null; then
  error "command npm could not be found, install it and re-run this script"
  exit 1
fi


### Setup
title "Starting setup"

reset_repo_to_initial_state
checkout_repo

tag_staging
git switch main

success "Setup complete!"


title "Scenario #1: Merge a pull request while the checklist is unlocked"

info "Creating PR #1..."
setup_git_as_human
git switch -c pr-1
echo "Changes from PR #1" >> PR1.txt
git add PR1.txt
git commit -m "Changes from PR #1"
success "Created PR #1 in branch pr-1"

merge_pr 1
bump_version patch
update_staging_from_main

# Tag staging
tag_staging
git switch main

# Verify output for checklist and deploy comment
assert_prs_merged_between '1.0.0' '1.0.1' "[ '1' ]"

success "Scenario #1 completed successfully!"


title "Scenario #2: Merge a pull request with the checklist locked, but don't CP it"

info "Creating PR #2..."
setup_git_as_human
git switch -c pr-2
echo "Changes from PR #2" >> PR2.txt
git add PR2.txt
git commit -m "Changes from PR #2"
merge_pr 2

success "Scenario #2 completed successfully!"

title "Scenario #3: Merge a pull request with the checklist locked and CP it to staging"

info "Creating PR #3 and merging it into main..."
git switch -c pr-3
echo "Changes from PR #3" >> PR3.txt
git add PR3.txt
git commit -m "Changes from PR #3"
cherry_pick_pr 3

tag_staging

# Verify output for checklist
assert_prs_merged_between '1.0.0' '1.0.2' "[ '3', '1' ]"

# Verify output for deploy comment
assert_prs_merged_between '1.0.1' '1.0.2' "[ '3' ]"

success "Scenario #3 completed successfully!"


title "Scenario #4: Close the checklist"
title "Scenario #4A: Run the production deploy"

update_production_from_staging

# Verify output for release body and production deploy comments
assert_prs_merged_between '1.0.0' '1.0.2' "[ '3', '1' ]"

success "Scenario #4A completed successfully!"

title "Scenario #4B: Run the staging deploy and create a new checklist"

bump_version minor
update_staging_from_main
tag_staging

# Verify output for new checklist and staging deploy comments
assert_prs_merged_between '1.0.2' '1.1.0' "[ '2' ]"

success "Scenario #4B completed successfully!"


title "Scenario #5: Merging another pull request when the checklist is unlocked"

info "Creating PR #5..."
setup_git_as_human
git switch main
git switch -c pr-5
echo "Changes from PR #5" >> PR5.txt
git add PR5.txt
git commit -m "Changes from PR #5"
merge_pr 5

bump_version patch
update_staging_from_main
tag_staging

# Verify output for checklist
assert_prs_merged_between '1.0.2' '1.1.1' "[ '5', '2' ]"

# Verify output for deploy comment
assert_prs_merged_between '1.1.0' '1.1.1' "[ '5' ]"

success "Scenario #5 completed successfully!"

title "Scenario #6: Deploying a PR, then CPing a revert, then adding the same code back again before the next production deploy results in the correct code on staging and production."

info "Creating myFile.txt in PR #6"
setup_git_as_human
git switch main
git switch -c pr-6
echo "Changes from PR #6" >> myFile.txt
git add myFile.txt
git commit -m "Add myFile.txt in PR #6"

merge_pr 6
bump_version patch
update_staging_from_main
tag_staging

# Verify output for checklist
assert_prs_merged_between '1.0.2' '1.1.2' "[ '6', '5', '2' ]"

# Verify output for deploy comment
assert_prs_merged_between '1.1.1' '1.1.2' "[ '6' ]"

info "Appending and prepending content to myFile.txt in PR #7"
setup_git_as_human
git switch main
git switch -c pr-7
printf "[DEBUG] Before:\n\n%s" "$(cat myFile.txt)"
printf "Prepended content\n%s" "$(cat myFile.txt)" > myFile.txt
printf "\nAppended content\n" >> myFile.txt
printf "\n\n[DEBUG] After:\n\n%s\n" "$(cat myFile.txt)"
git add myFile.txt
git commit -m "Append and prepend content in myFile.txt"

merge_pr 7
bump_version patch
update_staging_from_main
tag_staging

# Verify output for checklist
assert_prs_merged_between '1.0.2' '1.1.3' "[ '7', '6', '5', '2' ]"

# Verify output for deploy comment
assert_prs_merged_between '1.1.2' '1.1.3' "[ '7' ]"

info "Making an unrelated change in PR #8"
setup_git_as_human
git switch main
git switch -c pr-8
echo "some content" >> anotherFile.txt
git add anotherFile.txt
git commit -m "Create another file"

merge_pr 8

info "Reverting the append + prepend on main in PR #9"
setup_git_as_human
git switch main
git switch -c pr-9
printf "Before:\n\n%s\n" "$(cat myFile.txt)"
echo "some content" > myFile.txt
printf "\nAfter:\n\n%s\n" "$(cat myFile.txt)"
git add myFile.txt
git commit -m "Revert append and prepend"

cherry_pick_pr 9
tag_staging

info "Verifying that the revert is present on staging, but the unrelated change is not"
if [[ "$(cat myFile.txt)" != "some content" ]]; then
  error "Revert did not make it to staging"
  exit 1
else
  success "Revert made it to staging"
fi
if [[ -f anotherFile.txt ]]; then
  error "Unrelated change made it to staging"
  exit 1
else
  success "Unrelated change not on staging yet"
fi

info "Repeating previously reverted append + prepend on main in PR #10"
setup_git_as_human
git switch main
git switch -c pr-10
printf "[DEBUG] Before:\n\n%s" "$(cat myFile.txt)"
printf "Prepended content\n%s" "$(cat myFile.txt)" > myFile.txt
printf "\nAppended content\n" >> myFile.txt
printf "\n\n[DEBUG] After:\n\n%s\n" "$(cat myFile.txt)"
git add myFile.txt
git commit -m "Append and prepend content in myFile.txt"

merge_pr 10
update_production_from_staging
bump_version minor
update_staging_from_main
tag_staging

# Verify production release list
assert_prs_merged_between '1.0.2' '1.1.4' "[ '9', '7', '6', '5', '2' ]"

# Verify PR list for the new checklist
assert_prs_merged_between '1.1.4' '1.2.0' "[ '10', '8' ]"

### Cleanup
title "Cleaning up..."
cd "$TEST_DIR" || exit 1
rm -rf "$DUMMY_DIR"
success "All tests passed! Hooray!"
