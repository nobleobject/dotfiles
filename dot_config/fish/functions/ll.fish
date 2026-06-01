function ll --wraps=ls --wraps='eza -la --icons --git' --description 'alias ll=eza -la --icons --git'
    eza -la --icons --git $argv
end
