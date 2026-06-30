function ll --wraps=ls --wraps='eza -la --icons --git --sort=modified' --description 'alias ll=eza -la --icons --git --sort=modified'
    eza -la --icons --git --sort=modified $argv
end
