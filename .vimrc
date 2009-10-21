set bg=dark
set history=1000
set ignorecase
set smartcase
set title
set scrolloff=3
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set ruler
set showmatch
set incsearch
set hlsearch
set noai
set tabstop=4
set shiftwidth=4
set expandtab


syntax on
filetype on
filetype plugin on
filetype indent off

"" Highlight search terms...
set hlsearch
set incsearch " ...dynamically as they are typed.

set laststatus=2
let g:buftabs_in_statusline=1

highlight OverLength ctermbg=red ctermfg=white guibg=#592929
match OverLength /\%121v.*/

map ,pt <ESC>:%! perltidy<CR>
map ,ptv <ESC>:'<,'>! perltidy<CR>
