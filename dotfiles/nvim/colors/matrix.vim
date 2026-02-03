" Vim Color File
" Name:       matrix-green.vim
" Version:    1.0
" Maintainer: Based on bow-wob.vim by github.com/p7g
" License:    The MIT License (MIT)
" Description: Matrix-style green theme with black background

hi clear

if exists('syntax on')
    syntax reset
endif

let g:colors_name='matrix-green'

" not all terminals support italics properly. If yours does not, opt-out.
if ! exists('g:matrix_green_terminal_italics')
  let g:matrix_green_terminal_italics = 1
endif

if ! exists('g:matrix_green_spell_undercurl')
  let g:matrix_green_spell_undercurl = 1
endif

" Colors - Matrix Green Palette
let s:black = {'gui': '#000000', 'cterm': '0'}
let s:deep_green = {'gui': '#056608', 'cterm': '22'}
let s:verse_green = {'gui': '#147917', 'cterm': '28'}
let s:forest_green = {'gui': '#248D27', 'cterm': '34'}
let s:wageningen_green = {'gui': '#33A036', 'cterm': '70'}
let s:american_green = {'gui': '#43B446', 'cterm': '76'}
let s:apple_green = {'gui': '#52C755', 'cterm': '82'}

" Background and foreground
let s:bg = s:black
let s:fg = s:apple_green
let s:grey = s:forest_green
let s:dark_grey = s:verse_green
let s:light_grey = s:wageningen_green

if g:matrix_green_spell_undercurl == 1
  let s:sp_un = 'undercurl'
else
  let s:sp_un = 'underline'
endif

" shamelessly stolen from hemisu: https://github.com/noahfrederick/vim-hemisu/
function! s:h(group, style)
  " Not all terminals support italics properly. If yours does, opt-in.
  if g:matrix_green_terminal_italics == 0
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

call s:h('Constant',      {'fg': s:american_green, 'gui': 'italic', 'cterm': 'italic'})
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

call s:h('PreProc',       {'fg': s:wageningen_green})
hi! link Include          PreProc
hi! link Define           PreProc
hi! link Macro            PreProc
hi! link PreCondit        PreProc

call s:h('Type',          {'fg': s:american_green})
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
call s:h('Error',      {'fg': s:fg, 'bg': s:deep_green, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Todo',       {'fg': s:bg, 'bg': s:wageningen_green, 'gui': 'bold', 'cterm': 'bold'})

" ui chrome ====================================================================
" ordered according to `:help hitest.vim`

call s:h('SpecialKey',    {'fg': s:dark_grey})
call s:h('NonText',       {'fg': s:dark_grey})
call s:h('Directory',     {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('ErrorMsg',      {'fg': s:fg, 'bg': s:deep_green})
call s:h('IncSearch',     {'bg': s:american_green, 'fg': s:bg})
call s:h('Search',        {'bg': s:verse_green, 'fg': s:fg})
call s:h('MoreMsg',       {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
hi! link ModeMsg MoreMsg
call s:h('LineNr',        {'fg': s:grey})
call s:h('CursorLineNr',  {'fg': s:fg, 'bg': s:bg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Question',      {'fg': s:fg})
call s:h('StatusLine',    {'bg': s:deep_green, 'fg': s:fg})
call s:h('Conceal',       {'fg': s:dark_grey})
call s:h('StatusLineNC',  {'bg': s:deep_green, 'fg': s:grey})
call s:h('VertSplit',     {'bg': s:bg, 'fg': s:verse_green})
call s:h('Title',         {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Visual',        {'bg': s:forest_green, 'fg': s:bg})
call s:h('VisualNOS',     {'bg': s:verse_green})
call s:h('WarningMsg',    {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('WildMenu',      {'fg': s:bg, 'bg': s:american_green})
call s:h('Folded',        {'fg': s:grey, 'bg': s:deep_green})
call s:h('FoldColumn',    {'fg': s:grey, 'bg': s:bg})
call s:h('DiffAdd',       {'bg': s:deep_green, 'fg': s:american_green})
call s:h('DiffDelete',    {'bg': s:deep_green, 'fg': s:verse_green})
call s:h('DiffChange',    {'bg': s:verse_green, 'fg': s:fg})
call s:h('DiffText',      {'bg': s:forest_green, 'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('SignColumn',    {'fg': s:grey, 'bg': s:bg})

if has('gui_running')
  call s:h('SpellBad',    {'gui': s:sp_un, 'sp': s:american_green})
  call s:h('SpellCap',    {'gui': s:sp_un, 'sp': s:wageningen_green})
  call s:h('SpellRare',   {'gui': s:sp_un, 'sp': s:forest_green})
  call s:h('SpellLocal',  {'gui': s:sp_un, 'sp': s:verse_green})
else
  call s:h('SpellBad',    {'cterm': s:sp_un, 'fg': s:american_green})
  call s:h('SpellCap',    {'cterm': s:sp_un, 'fg': s:wageningen_green})
  call s:h('SpellRare',   {'cterm': s:sp_un, 'fg': s:forest_green})
  call s:h('SpellLocal',  {'cterm': s:sp_un, 'fg': s:verse_green})
endif

call s:h('Pmenu',         {'fg': s:fg, 'bg': s:verse_green})
call s:h('PmenuSel',      {'fg': s:bg, 'bg': s:american_green, 'gui': 'bold', 'cterm': 'bold'})
call s:h('PmenuSbar',     {'fg': s:fg, 'bg': s:deep_green})
call s:h('PmenuThumb',    {'fg': s:fg, 'bg': s:forest_green})
call s:h('NormalFloat',   {'fg': s:fg, 'bg': s:black})
call s:h('TabLine',       {'fg': s:grey, 'bg': s:deep_green})
call s:h('TabLineSel',    {'fg': s:fg, 'bg': s:bg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('TabLineFill',   {'fg': s:verse_green, 'bg': s:deep_green})
call s:h('CursorColumn',  {'bg': s:deep_green})
call s:h('CursorLine',    {'bg': s:deep_green})
call s:h('ColorColumn',   {'bg': s:deep_green})

" remainder of syntax highlighting
call s:h('MatchParen',    {'bg': s:verse_green, 'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('qfLineNr',      {'fg': s:grey})

" HTML syntax
hi! link htmlTag          Special
hi! link htmlEndTag       htmlTag

hi! link htmlTagName      KeyWord
" html5 tags show up as htmlTagN
hi! link htmlTagN         Keyword

" HTML content
call s:h('htmlH1',        {'fg': s:fg, 'gui': 'bold,italic', 'cterm': 'bold'     })
call s:h('htmlH2',        {'fg': s:american_green, 'gui': 'bold'       , 'cterm': 'bold'     })
call s:h('htmlH3',        {'fg': s:wageningen_green, 'gui': 'italic'     , 'cterm': 'italic'   })
call s:h('htmlH4',        {'fg': s:wageningen_green, 'gui': 'italic'     , 'cterm': 'italic'   })
call s:h('htmlH5',        {'fg': s:forest_green                                            })
call s:h('htmlH6',        {'fg': s:forest_green                                            })
call s:h('htmlLink',      {'fg': s:american_green, 'gui': 'underline'  , 'cterm': 'underline'})
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
