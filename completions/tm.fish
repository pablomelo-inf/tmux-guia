# fish completion for tm. "tm link" installs it in ~/.config/fish/completions.
complete -c tm -f
complete -c tm -n __fish_use_subcommand -a "(tm _commands --describe 2>/dev/null | string replace ':' \t)"
complete -c tm -n "__fish_seen_subcommand_from attach create detach kill rename open" -a "(tm _sessions 2>/dev/null)"
complete -c tm -n "__fish_seen_subcommand_from attach create" -a "(__fish_complete_directories)"
complete -c tm -n "__fish_seen_subcommand_from open" -l all -d "Include sessions in use"
complete -c tm -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
