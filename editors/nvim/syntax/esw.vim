" ESW: HTML with embedded Swift. No external parser required.
if exists('b:current_syntax')
  finish
endif

runtime! syntax/html.vim
unlet! b:current_syntax
syntax case match
syntax include @eswSwift syntax/swift.vim
unlet! b:current_syntax

" Keep template boundaries authoritative across incomplete Swift statements,
" but allow complete strings/comments to contain literal template delimiters.
syntax match eswSwiftIdentifier /\<[[:alpha:]_][[:alnum:]_]*\>/ contained
syntax match eswSwiftType /\<[A-Z][[:alnum:]_]*\>/ contained
syntax match eswSwiftFunction /\<[[:alpha:]_][[:alnum:]_]*\>\ze\s*(/ contained
syntax region eswSwiftString start=+\z(#*\)\z("""\|"\)+ skip=+\\\z1\_.+ end=+\z2\z1+ contained extend contains=eswSwiftInterpolation
syntax region eswSwiftInterpolation matchgroup=Special start=+\\#*(+ end=+)+ contained contains=@eswSwift
syntax region eswSwiftParen matchgroup=Delimiter start=+(+ end=+)+ contained transparent contains=@eswSwift
syntax region eswSwiftComment start=+/\*+ end=+\*/+ contained extend contains=eswSwiftComment,swiftTodo,@Spell
syntax region eswSwiftLineComment start=+//+ end=+$+ contained extend contains=swiftTodo,@Spell
syntax cluster eswSwift add=eswSwiftIdentifier,eswSwiftType,eswSwiftFunction,eswSwiftString,eswSwiftParen,eswSwiftComment,eswSwiftLineComment
syntax cluster eswRegions contains=eswCode,eswComment,eswBlockComment,eswEscape,eswExpression,eswNestedBrace,eswSwiftInterpolation

syntax region eswCode matchgroup=eswDelimiter start=+<%\%(%\|#\|!--\)\@!\%(==\|[=!]\)\?+ skip=+%%>+ end=+%>+ keepend contains=@eswSwift containedin=ALLBUT,@eswRegions,@eswSwift
syntax region eswComment start=+<%#+ skip=+%%>+ end=+%>+ keepend contains=swiftTodo,@Spell containedin=ALLBUT,@eswRegions,@eswSwift
syntax region eswBlockComment start=+<%!--+ end=+--%>+ keepend contains=swiftTodo,@Spell containedin=ALLBUT,@eswRegions,@eswSwift
syntax match eswEscape +<%%\|%%>+ containedin=ALLBUT,@eswRegions,@eswSwift
syntax cluster htmlPreproc add=eswCode,eswComment,eswBlockComment,eswEscape

" HTML's default tag-name rules do not include ESW components or named slots.
syntax match eswComponentName +</\?\zs\%(\.[[:alnum:]_-]\+\|[A-Z][[:alnum:]_]*\%(\.[[:alnum:]_]\+\)\+\|:[[:alnum:]_-]\+\)+ containedin=htmlTag,htmlEndTag,htmlTagN
syntax match eswDirective /:\%(if\|for\|key\|let\)\>/ containedin=htmlTag

" Component attributes accept Swift braces even in the text-oriented .esw mode.
syntax region eswComponentTag start=+<\%(\.[[:alnum:]_-]\+\|[A-Z][[:alnum:]_]*\%(\.[[:alnum:]_]\+\)\+\|:[[:alnum:]_-]\+\)\ze\%(\s\|/\?>\)+ end=+>+ contains=eswComponentName,htmlString,htmlArg,eswDirective,eswExpression,@htmlPreproc
syntax region eswNestedBrace matchgroup=eswDelimiter start=+{+ end=+}+ contained extend contains=@eswSwift,eswNestedBrace
syntax region eswExpression matchgroup=eswDelimiter start=+{+ end=+}+ contained keepend contains=@eswSwift,eswNestedBrace

if &filetype ==# 'hesw'
  " Body expressions and unquoted HTML attributes. Quoted attributes, scripts,
  " styles, and HTML comments retain their host-language brace highlighting.
  syntax region eswExpression matchgroup=eswDelimiter start=+\\\@<!{+ end=+}+ keepend contains=@eswSwift,eswNestedBrace containedin=htmlTag,htmlValue,htmlBold,htmlItalic,htmlUnderline,htmlStrike,htmlLink,htmlHead,htmlTitle,htmlH1,htmlH2,htmlH3,htmlH4,htmlH5,htmlH6
endif

highlight default link eswDelimiter PreProc
highlight default link eswComment Comment
highlight default link eswBlockComment Comment
highlight default link eswEscape SpecialChar
highlight default link eswComponentTag htmlTag
highlight default link eswComponentName Type
highlight default link eswDirective PreProc
highlight default link eswSwiftIdentifier Identifier
highlight default link eswSwiftType Type
highlight default link eswSwiftFunction Function
highlight default link eswSwiftString String
highlight default link eswSwiftComment Comment
highlight default link eswSwiftLineComment Comment

syntax sync fromstart
let b:current_syntax = &filetype ==# 'hesw' ? 'hesw' : 'esw'
