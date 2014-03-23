 "coloring
colorscheme desert
syntax on
:hi LineNr ctermfg=blue ctermbg=black

set t_Co=256
" etc
set number
set nowrap

" tabbing
set tabstop=4
set shiftwidth=4
set expandtab

"set cindent
set smartindent
let mapleader = ","

" Vundle config
set rtp+=~/.vim/bundle/vundle
call vundle#rc()

Bundle 'gmarik/vundle'

Bundle 'vim-scripts/guicolorscheme.vim'
Bundle 'scrooloose/nerdtree'
Bundle 'saleh/vim-supertab'
"Bundle 'vim-scripts/SearchComplete'
Bundle 'vim-scripts/taglist.vim'
Bundle 'scrooloose/nerdcommenter'
Bundle 'scrooloose/syntastic'
Bundle 'vim-scripts/mru.vim'
Bundle 'mileszs/ack.vim.git'
Bundle 'vim-scripts/jsbeautify.git'
Bundle 'Valloric/YouCompleteMe'
"Bundle 'davidhalter/jedi-vim'

filetype plugin indent on
" disable annoying bell
set visualbell t_vb=

" edit .vimrc
nmap <leader>s :source $MYVIMRC<cr>
nmap <leader>ev :e $MYVIMRC<cr>

" searching
set ignorecase
set showmatch
set hlsearch

" NERD tree
map <F12> :NERDTreeToggle<cr>
let NERDTreeIgnore=['.vim$', '\~$', '.*\.pyc$', 'pip-log\.txt$', '.DS_Store$']
let NERDTreeShowBookmarks=1
let NERDTreeQuitOnOpen=1
let NERDTreeDirArrows=1
let g:NERDTreeChDirMode=2

" taglist
map <F5> :TlistToggle<cr>
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'

" text navigation key mappings
map H <Esc>:bn<cr>
map L <Esc>:bp<cr>
map F <Esc><c-w><c-w><CR>
inoremap jj <Esc>
map - $

" window key mappings
nmap W <Esc><c-w>H
map <C-h> <Esc>:tabprevious<cr>
map <C-l> <Esc>:tabNext<cr>
" edit key mappings
:nnoremap S <esc>:noh<return><esc>:let @/ = ""<return>
":vmap C :s/^/#<CR>S 
":vmap c :s/^./<CR>S

nnoremap <F2> :set invpaste paste?<CR>
set pastetoggle=<F2>
set showmode



"here is a more exotic version of my original Kwbd script
"delete the buffer; keep windows; create a scratch buffer if no buffers left
function s:Kwbd(kwbdStage)
  if(a:kwbdStage == 1)
    if(!buflisted(winbufnr(0)))
      bd!
      return
    endif
    let s:kwbdBufNum = bufnr("%")
    let s:kwbdWinNum = winnr()
    windo call s:Kwbd(2)
    execute s:kwbdWinNum . 'wincmd w'
    let s:buflistedLeft = 0
    let s:bufFinalJump = 0
    let l:nBufs = bufnr("$")
    let l:i = 1
    while(l:i <= l:nBufs)
      if(l:i != s:kwbdBufNum)
        if(buflisted(l:i))
          let s:buflistedLeft = s:buflistedLeft + 1
        else
          if(bufexists(l:i) && !strlen(bufname(l:i)) && !s:bufFinalJump)
            let s:bufFinalJump = l:i
          endif
        endif
      endif
      let l:i = l:i + 1
    endwhile
    if(!s:buflistedLeft)
      if(s:bufFinalJump)
        windo if(buflisted(winbufnr(0))) | execute "b! " . s:bufFinalJump | endif
      else
        enew
        let l:newBuf = bufnr("%")
        windo if(buflisted(winbufnr(0))) | execute "b! " . l:newBuf | endif
      endif
      execute s:kwbdWinNum . 'wincmd w'
    endif
    if(buflisted(s:kwbdBufNum) || s:kwbdBufNum == bufnr("%"))
      execute "bd! " . s:kwbdBufNum
    endif
    if(!s:buflistedLeft)
      set buflisted
      set bufhidden=delete
      set buftype=
      setlocal noswapfile
    endif
  else
    if(bufnr("%") == s:kwbdBufNum)
      let prevbufvar = bufnr("#")
      if(prevbufvar > 0 && buflisted(prevbufvar) && prevbufvar != s:kwbdBufNum)
        b #
      else
        bn
      endif
    endif
  endif
endfunction

command! Kwbd call s:Kwbd(1)
nnoremap <silent> <Plug>bd :<C-u>Kwbd<CR>

" Create a mapping (e.g. in your .vimrc) like this:
"nmap <C-W>! <Plug>Kwbd
