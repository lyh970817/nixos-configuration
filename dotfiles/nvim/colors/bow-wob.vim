" Vim Color File
" Name:       bow.vim (Textured Edition)
" Version:    0.2
" Maintainer: github.com/p7g
" License:    The MIT License (MIT)

hi clear

if exists('syntax on')
    syntax reset
endif

let g:colors_name='bow-wob'

" Force italics support
if ! exists('g:bow_wob_terminal_italics')
  let g:bow_wob_terminal_italics = 1
endif

if ! exists('g:bow_wob_spell_undercurl')
  let g:bow_wob_spell_undercurl = 1
endif

" --- PALETTE (Strictly keeping your original colors) ---
let s:black = {'gui': '#000000', 'cterm': '0'}
let s:white = {'gui': '#FFFFFF', 'cterm': '15'}
let s:light_grey = {'gui': '#cccccc', 'cterm': '7'}
let s:dark_grey = {'gui': '#333333', 'cterm': '8'}

let s:bg = s:white
let s:fg = s:black
let s:grey = s:light_grey

if g:bow_wob_spell_undercurl == 1
  let s:sp_un = 'undercurl'
else
  let s:sp_un = 'underline'
endif

" Helper function
function! s:h(group, style)
  if g:bow_wob_terminal_italics == 0 && has_key(a:style, 'cterm') && a:style['cterm'] == 'italic'
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

" ==============================================================================
" CORE HIGHLIGHTING (The Texture)
" ==============================================================================

call s:h('Normal',        {'bg': s:bg, 'fg': s:fg})
call s:h('Cursor',        {'bg': s:fg, 'fg': s:bg})

" 1. COMMENTS: Italic
"    Keeps comments subtle and distinct from code logic.
call s:h('Comment',       {'fg': s:fg, 'gui': 'italic', 'cterm': 'italic'})

" 2. CONSTANTS (String, Number, Bool): Italic
"    Data should look different than logic.
call s:h('Constant',      {'fg': s:fg, 'gui': 'italic', 'cterm': 'italic'})
hi! link String           Constant
hi! link Character        Constant
hi! link Number           Constant
hi! link Boolean          Constant
hi! link Float            Constant

" 3. IDENTIFIERS (Variables): Plain
"    This is the baseline. If everything is bold, nothing is bold.
call s:h('Identifier',    {'fg': s:fg})

" 4. FUNCTIONS: Bold
"    Make function names pop out so you can scan file structure easily.
call s:h('Function',      {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})

" 5. STATEMENTS (Keywords, if, else, return): Bold
"    Control flow should be heavy.
call s:h('Statement',     {'fg': s:fg, 'cterm': 'bold', 'gui': 'bold'})
hi! link Conditional      Statement
hi! link Repeat           Statement
hi! link Label            Statement
hi! link Operator         Statement
hi! link Keyword          Statement
hi! link Exception        Statement

" 6. PREPROC / MACROS: Bold Italic
"    Things like #define or @Decorators should look "special".
call s:h('PreProc',       {'fg': s:fg, 'gui': 'bold,italic', 'cterm': 'bold,italic'})
hi! link Include          PreProc
hi! link Define           PreProc
hi! link Macro            PreProc
hi! link PreCondit        PreProc

" 7. TYPES (Classes, Structs): Underline
"    This gives Types a distinct "blueprint" feel without adding more boldness.
call s:h('Type',          {'fg': s:fg, 'gui': 'underline', 'cterm': 'underline'})
hi! link StorageClass     Type
hi! link Structure        Type
hi! link Typedef          Type

" 8. SPECIAL (Delimiters, brackets): Plain
call s:h('Special',       {'fg': s:fg})
hi! link SpecialChar      Special
hi! link Tag              Special
hi! link Delimiter        Special
hi! link SpecialComment   Special
hi! link Debug            Special

call s:h('Underlined', {'fg': s:fg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('Ignore',     {'fg': s:bg})
call s:h('Error',      {'fg': s:fg, 'bg': s:grey, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Todo',       {'fg': s:fg, 'bg': s:grey, 'gui': 'bold,italic', 'cterm': 'bold,italic'})

" ==============================================================================
" UI CHROME
" ==============================================================================

call s:h('SpecialKey',    {'fg': s:grey})
call s:h('NonText',       {'fg': s:grey})
call s:h('Directory',     {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('ErrorMsg',      {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('IncSearch',     {'bg': s:fg, 'fg': s:bg})
call s:h('Search',        {'bg': s:bg, 'gui': 'underline,bold', 'cterm': 'underline,bold'})
call s:h('MoreMsg',       {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
hi! link ModeMsg MoreMsg
call s:h('LineNr',        {'fg': s:grey})
call s:h('CursorLineNr',  {'fg': s:fg, 'bg': s:bg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Question',      {'fg': s:fg})
call s:h('StatusLine',    {'bg': s:bg, 'gui': 'bold,underline', 'cterm': 'bold,underline'})
call s:h('Conceal',       {'fg': s:grey})
call s:h('StatusLineNC',  {'bg': s:bg, 'fg': s:fg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('VertSplit',     {'bg': s:bg, 'fg': s:fg})
call s:h('Title',         {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('Visual',        {'bg': s:fg, 'fg': s:bg})
call s:h('VisualNOS',     {'bg': s:bg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('WarningMsg',    {'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('WildMenu',      {'fg': s:fg, 'bg': s:grey})
call s:h('Folded',        {'fg': s:fg, 'gui': 'italic', 'cterm': 'italic'})
call s:h('FoldColumn',    {'fg': s:bg})
call s:h('DiffText',      {'bg': s:bg, 'fg': s:fg, 'gui': 'bold', 'cterm': 'bold'})
call s:h('SignColumn',    {'fg': s:fg})

if has('gui_running')
  call s:h('SpellBad',    {'gui': s:sp_un, 'sp': s:fg})
  call s:h('SpellCap',    {'gui': s:sp_un, 'sp': s:fg})
  call s:h('SpellRare',   {'gui': s:sp_un, 'sp': s:fg})
  call s:h('SpellLocal',  {'gui': s:sp_un, 'sp': s:fg})
else
  call s:h('SpellBad',    {'cterm': s:sp_un, 'fg': s:fg})
  call s:h('SpellCap',    {'cterm': s:sp_un, 'fg': s:fg})
  call s:h('SpellRare',   {'cterm': s:sp_un, 'fg': s:fg})
  call s:h('SpellLocal',  {'cterm': s:sp_un, 'fg': s:fg})
endif

call s:h('Pmenu',         {'fg': s:fg, 'bg': s:grey})
call s:h('PmenuSel',      {'fg': s:bg, 'bg': s:fg})
call s:h('PmenuSbar',     {'fg': s:fg, 'bg': s:grey})
call s:h('PmenuThumb',    {'fg': s:fg, 'bg': s:grey})
call s:h('NormalFloat',   {'fg': s:fg, 'bg': s:bg})
call s:h('TabLine',       {'fg': s:fg, 'bg': s:bg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('TabLineSel',    {'fg': s:fg, 'bg': s:bg, 'gui': 'bold,underline', 'cterm': 'bold,underline'})
call s:h('TabLineFill',   {'fg': s:fg, 'bg': s:bg, 'gui': 'underline', 'cterm': 'underline'})
call s:h('CursorColumn',  {'bg': s:grey})
call s:h('CursorLine',    {'bg': s:grey})
call s:h('ColorColumn',   {'bg': s:grey})
call s:h('MatchParen',    {'bg': s:bg, 'fg': s:fg, 'gui': 'bold,underline', 'cterm': 'bold,underline'})
call s:h('qfLineNr',      {'fg': s:grey})

" ==============================================================================
" TREE-SITTER SPECIFIC OVERRIDES
" Use the AST to distinguish concepts that standard Regex can't.
" ==============================================================================

" Make parameters Italic so they look distinct from local variables
hi! link @variable.parameter Constant
" Make builtin variables (this, self) Bold Italic
hi! link @variable.builtin   PreProc

" Make Function calls Bold (same as definition)
hi! link @function           Function
hi! link @function.call      Function
hi! link @method             Function
hi! link @method.call        Function

" Make Properties (obj.prop) Italic
hi! link @property           Constant
hi! link @field              Constant

" Make Constructors Bold/Underlined
hi! link @constructor        Type

" Make Punctuation (brackets) Plain
hi! link @punctuation        Special

" HTML/XML specific
hi! link htmlTag           Statement
hi! link htmlEndTag        Statement
hi! link htmlTagName       Statement
hi! link htmlArg           Constant
hi! link xmlTag            Statement
hi! link xmlEndTag         Statement
hi! link xmlTagName        Statement
