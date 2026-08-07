" Vim Color File
" Name:       vt220-amber.vim
" Version:    1.0
" Maintainer: Based on bow-wob.vim by github.com/p7g
" License:    The MIT License (MIT)
" Description: VT220 Amber-style amber theme with black background

hi clear

if exists('syntax on')
    syntax reset
endif

let g:colors_name='vt220-amber'

" not all terminals support italics properly. If yours does not, opt-out.
if ! exists('g:vt220-amber_amber_terminal_italics')
  let g:vt220-amber_amber_terminal_italics = 1
endif

if ! exists('g:vt220-amber_amber_spell_undercurl')
  let g:vt220-amber_amber_spell_undercurl = 1
endif

" Colors - VT220 Amber Palette
let s:black = {'gui': '#080705', 'cterm': '0'}
let s:deep_amber = {'gui': '#0C0A06', 'cterm': '22'}
let s:subtle_border = {'gui': '#2A2011', 'cterm': '28'}
let s:muted_amber = {'gui': '#6E501D', 'cterm': '34'}
let s:secondary_amber = {'gui': '#9B6D24', 'cterm': '70'}
let s:accent_amber = {'gui': '#BE842A', 'cterm': '76'}
let s:amber = {'gui': '#D99B32', 'cterm': '82'}

" Background and foreground
let s:bg = s:black
let s:fg = s:amber
let s:grey = s:muted_amber
let s:dark_grey = s:subtle_border
let s:light_grey = s:secondary_amber

if g:vt220-amber_amber_spell_undercurl == 1
  let s:sp_un = 'undercurl'
else
  let s:sp_un = 'underline'
endif

" shamelessly stolen from hemisu: https://github.com/noahfrederick/vim-hemisu/
function! s:h(group, style)
  " Not all terminals support italics properly. If yours does, opt-in.
  if g:vt220-amber_amber_terminal_italics == 0
        \ && has_key(a:style, 'cterm')
        \ && a:style['cterm'] == 'italic'
    unlet a:style.cterm
  endif
  execute 'highlight' a:group
    \ 'guifg='   (has_key(a:style, 'fg')    ? a:style.fg.gui   : 'NONE')
    \ 'guibg='   (has_key(a:style, 'bg')    ? a:style.bg.gui   : 'NONE')
    \ 'guisp='   (has_key(a:style, 'sp')    ? a:style.sp.gui   : 'NONE')
    \ 'gui='     (has_key(a:style, 'gui')   ? a:style.gui      : 'NONE')
    \ 'ctermfg=' (has_key(a:style, 'fg')    ? a:style.fg.cterm : 'NONE')
    \ 'ctermbg=' (has_key(a:style, 'bg')    ? a:style.bg.cterm : 'NONE')
    \ 'cterm='   (has_key(a:style, 'cterm') ? a:style.cterm    : 'NONE')
endfunction

" common groups ================================================================
" (see `:h w18`)

call s:h('Normal',        {'bg': s:bg, 'fg': s:fg})
call s:h('Cursor',        {'bg': s:fg, 'fg': s:bg})
call s:h('Comment',       {'fg': s:grey, 'gui': 'italic', 'cterm': 'italic'})

call s:h('Constant',      {'fg': s:accent_amber, 'gui': 'italic', 'cterm': 'italic'})
hi! link String           Constant
hi! link Character        Constant
hi! link Number           Constant
hi! link Boolean          Constant
hi! link Float            Constant

call s:h('Identifier',    {'fg': s:fg})
hi! link Function         Identifier

call s:h('Statement',     {'fg': s:fg, 'cterm': 'bold', 'gui': 'bold'})
hi! link Conditonal       Statement
hi! link Repeat           Statement
hi! link Label            Statement
hi! link Operator         Statement
hi! link Keyword          Statement
hi! link Exception        Statement

call s:h('PreProc',       {'fg': s:secondary_amber})
hi! link Include          PreProc
hi! link Define           PreProc
hi! link Macro            PreProc
hi! link PreCondit        PreProc

call s:h('Type',          {'fg': s:accent_amber})
hi! link StorageClass     Type
hi! link Structure        Type
hi! link Typedef          Type

call s:h('Special',       {'fg': s:fg})
hi! link SpecialChar      Special
hi! link Tag              Special
hi! link Delimiter        Special
hi! link SpecialComment   Special
hi! link Debug            Special

call s:h('Underlined', {'fg': s:fg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('Ignore',     {'fg': s:bg})
call s:h('Error',      {'fg': s:fg, 'bg': s:deep_amber, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Todo',       {'fg': s:bg, 'bg': s:secondary_amber, 'gui': 'bold', 'cterm': 'bold'})

" ui chrome ====================================================================
" ordered according to `:help hitest.vim`

call s:h('SpecialKey',    {'fg': s:dark_grey})
call s:h('NonText',       {'fg': s:dark_grey})
call s:h('Directory',     {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('ErrorMsg',      {'fg': s:fg, 'bg': s:deep_amber})
call s:h('IncSearch',     {'bg': s:accent_amber, 'fg': s:bg})
call s:h('Search',        {'bg': s:subtle_border, 'fg': s:fg})
call s:h('MoreMsg',       {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
hi! link ModeMsg MoreMsg
call s:h('LineNr',        {'fg': s:grey})
call s:h('CursorLineNr',  {'fg': s:fg, 'bg': s:bg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Question',      {'fg': s:fg})
call s:h('StatusLine',    {'bg': s:deep_amber, 'fg': s:fg})
call s:h('Conceal',       {'fg': s:dark_grey})
call s:h('StatusLineNC',  {'bg': s:deep_amber, 'fg': s:grey})
call s:h('VertSplit',     {'bg': s:bg, 'fg': s:subtle_border})
call s:h('Title',         {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Visual',        {'bg': s:muted_amber, 'fg': s:bg})
call s:h('VisualNOS',     {'bg': s:subtle_border})
call s:h('WarningMsg',    {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('WildMenu',      {'fg': s:bg, 'bg': s:accent_amber})
call s:h('Folded',        {'fg': s:grey, 'bg': s:deep_amber})
call s:h('FoldColumn',    {'fg': s:grey, 'bg': s:bg})
call s:h('DiffAdd',       {'bg': s:deep_amber, 'fg': s:accent_amber})
call s:h('DiffDelete',    {'bg': s:deep_amber, 'fg': s:subtle_border})
call s:h('DiffChange',    {'bg': s:subtle_border, 'fg': s:fg})
call s:h('DiffText',      {'bg': s:muted_amber, 'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('SignColumn',    {'fg': s:grey, 'bg': s:bg})

if has('gui_running')
  call s:h('SpellBad',    {'gui': s:sp_un, 'sp': s:accent_amber})
  call s:h('SpellCap',    {'gui': s:sp_un, 'sp': s:secondary_amber})
  call s:h('SpellRare',   {'gui': s:sp_un, 'sp': s:muted_amber})
  call s:h('SpellLocal',  {'gui': s:sp_un, 'sp': s:subtle_border})
else
  call s:h('SpellBad',    {'cterm': s:sp_un, 'fg': s:accent_amber})
  call s:h('SpellCap',    {'cterm': s:sp_un, 'fg': s:secondary_amber})
  call s:h('SpellRare',   {'cterm': s:sp_un, 'fg': s:muted_amber})
  call s:h('SpellLocal',  {'cterm': s:sp_un, 'fg': s:subtle_border})
endif

call s:h('Pmenu',         {'fg': s:fg, 'bg': s:subtle_border})
call s:h('PmenuSel',      {'fg': s:bg, 'bg': s:accent_amber, 'gui': 'bold', 'cterm': 'bold'})
call s:h('PmenuSbar',     {'fg': s:fg, 'bg': s:deep_amber})
call s:h('PmenuThumb',    {'fg': s:fg, 'bg': s:muted_amber})
call s:h('NormalFloat',   {'fg': s:fg, 'bg': s:black})
call s:h('TabLine',       {'fg': s:grey, 'bg': s:deep_amber})
call s:h('TabLineSel',    {'fg': s:fg, 'bg': s:bg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('TabLineFill',   {'fg': s:subtle_border, 'bg': s:deep_amber})
call s:h('CursorColumn',  {'bg': s:deep_amber})
call s:h('CursorLine',    {'bg': s:deep_amber})
call s:h('ColorColumn',   {'bg': s:deep_amber})

" remainder of syntax highlighting
call s:h('MatchParen',    {'bg': s:subtle_border, 'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('qfLineNr',      {'fg': s:grey})

" HTML syntax
hi! link htmlTag          Special
hi! link htmlEndTag       htmlTag

hi! link htmlTagName      KeyWord
" html5 tags show up as htmlTagN
hi! link htmlTagN         Keyword

" HTML content
call s:h('htmlH1',        {'fg': s:fg, 'gui': 'bold,italic', 'cterm': 'bold'     })
call s:h('htmlH2',        {'fg': s:accent_amber, 'gui': 'bold'       , 'cterm': 'bold'     })
call s:h('htmlH3',        {'fg': s:secondary_amber, 'gui': 'italic'     , 'cterm': 'italic'   })
call s:h('htmlH4',        {'fg': s:secondary_amber, 'gui': 'italic'     , 'cterm': 'italic'   })
call s:h('htmlH5',        {'fg': s:muted_amber                                            })
call s:h('htmlH6',        {'fg': s:muted_amber                                            })
call s:h('htmlLink',      {'fg': s:accent_amber, 'gui': 'underline'  , 'cterm': 'underline'})
call s:h('htmlItalic',    {            'gui': 'italic'     , 'cterm': 'italic'   })
call s:h('htmlBold',      {            'gui': 'bold'       , 'cterm': 'bold'     })
call s:h('htmlBoldItalic',{            'gui': 'bold,italic', 'cterm': 'bold'     })

" XML content
hi! link xmlTag                     htmlTag
hi! link xmlEndTag                  xmlTag
hi! link xmlTagName                 htmlTagName

" Treesitter highlights (if available)
hi! link @variable              Identifier
hi! link @variable.builtin      Special
hi! link @variable.parameter    Identifier
hi! link @variable.member       Identifier

hi! link @constant              Constant
hi! link @constant.builtin      Special
hi! link @constant.macro        Macro

hi! link @string                String
hi! link @string.escape         SpecialChar
hi! link @string.special        SpecialChar

hi! link @character             Character
hi! link @number                Number
hi! link @boolean               Boolean
hi! link @float                 Float

hi! link @function              Function
hi! link @function.builtin      Special
hi! link @function.macro        Macro
hi! link @function.method       Function

hi! link @constructor           Type
hi! link @parameter             Identifier

hi! link @keyword               Keyword
hi! link @keyword.function      Keyword
hi! link @keyword.operator      Operator
hi! link @keyword.return        Keyword

hi! link @conditional           Conditional
hi! link @repeat                Repeat
hi! link @label                 Label
hi! link @operator              Operator
hi! link @exception             Exception

hi! link @type                  Type
hi! link @type.builtin          Type
hi! link @type.definition       Typedef
hi! link @type.qualifier        Keyword

hi! link @structure             Structure
hi! link @include               Include
hi! link @preproc               PreProc
hi! link @define                Define
hi! link @macro                 Macro

hi! link @comment               Comment
hi! link @punctuation           Delimiter
hi! link @punctuation.bracket   Delimiter
hi! link @punctuation.delimiter Delimiter

hi! link @tag                   Tag
hi! link @tag.attribute         Identifier
hi! link @tag.delimiter         Delimiter
