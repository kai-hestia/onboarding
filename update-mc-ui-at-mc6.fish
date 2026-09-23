# Fish completions for update-mc-ui-at-mc6
#
# Install (symlink so repo edits apply immediately):
#   ln -sf ~/repos/onboarding/update-mc-ui-at-mc6.fish \
#          ~/.config/fish/completions/update-mc-ui-at-mc6.fish

complete -c update-mc-ui-at-mc6 -f
complete -c update-mc-ui-at-mc6 -s h -l help -d "show help"

complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a doctor   -d "check tools, repo, settings, ssh and mc-api access"
complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a build    -d "npm run build + validate tmp/ui.zip"
complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a backup   -d "snapshot the live /multicooker/ui from the device"
complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a rollback -d "upload a backup zip to the device"
complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a update   -d "full flow: build -> backup -> upload -> verify"
complete -c update-mc-ui-at-mc6 -n "__fish_use_subcommand" -a help     -d "show help"

# rollback <zip>: zip files under the mc-ui backups dir (full path, or a bare timestamp)
complete -c update-mc-ui-at-mc6 -n "__fish_seen_subcommand_from rollback" -a "(path filter -f $HOME/repos/mc-ui/backups/*.zip)"
