if exists("g:did_idrisIde") && g:did_idrisIde
   finish
end

let g:did_idrisIde = v:true

" ================== Parser and Utilities ========================

" Given the list `xs`, returns a new list
" where each element is a pair of the original one
" with its index counting from `i`
function! s:zipWithIndex(xs, i)
   if empty(a:xs)
      return []
   else
      return [[a:i, a:xs[0]]] + s:zipWithIndex(a:xs[1:], a:i + 1)
   endif
endfunction

" Checks if the first char of `str` is a digit
function! s:isDigit(str)
   return char2nr('0') <= char2nr(a:str) && char2nr(a:str) <= char2nr('9')
endfunction

" Returns the slice of the string starting from the char at `start`
" and ending with the char at `(end - 1)`
" If `(end - start <= 0)` returns the empty string
function! s:slice(str, start, end)
   if a:end - a:start <= 0
      return ""
   else
      return a:str[a:start : a:end-1]
   end
endfunction

" Result of the parser is defined as a dictionary with fields:
" `success` : bool, if the parse was successful
" `parsed`  : any value, the result
" `rest`    : string, the leftover string yet to be consumed
function! s:parseResult(ok, parsed, rest)
   return {'success' : a:ok, 'parsed' : a:parsed, 'rest' : a:rest}
endfunction

" Maps the result of the parse using the function `f`
function! s:mapToken(res, f)
   let res = deepcopy(a:res)
   let res['parsed'] = a:f(res['parsed'])
   return res
endfunction

function! s:parseNatural(str)
   let i = 0
   let ok = 1
   let res = ""
   let l = len(a:str)
   while i < l && ok
      if s:isDigit(a:str[i])
         let res .= a:str[i]
         let i += 1
      else
         let ok = 0
      endif
   endwhile
   return s:parseResult(i > 0 ? 1 : 0, s:slice(a:str, 0, i), s:slice(a:str, i, l))
endfunction

function! s:parseSymbol(str, symbol)
   if a:str[0] == a:symbol[0]
      return s:parseResult(1, a:str[0], s:slice(a:str, 1, len(a:str)))
   else
      return s:parseResult(0, "", a:str)
endfunction

" `string` must be non-empty
function! s:parseExact(str, string)
   if a:str =~ '^' . a:string
      return s:parseResult(1, s:slice(a:str, 0, len(a:string)), s:slice(a:str, len(a:string), len(a:str)))
   else
      return s:parseResult(0, "", a:str)
endfunction

function! s:parseCommand(str)
   let [m, _, e] = matchstrpos(a:str, '\v^:[a-zA-Z][a-zA-Z_\-0-9]*')
   if m == ""
      return s:parseResult(0, "", a:str)
   else
      return s:parseResult(1, s:slice(a:str, 0, e), s:slice(a:str, e, len(a:str)))
   endif
endfunction

function! s:parseString(str)
   let res = matchlist(a:str, '\v^"(%(\\.|[^"])*)"')
   if empty(res)
      return s:parseResult(0, "", a:str)
   else
      return s:parseResult(1, res[1], s:slice(a:str, len(res[0]), len(a:str)))
   endif
endfunction

" Parses zero or more tokens defined by `f`
function! s:parseMany(str, f)
   let res = []
   let rest = a:str
   while v:true
      let r = a:f(rest)
      if r['success']
         let res = add(res, r['parsed'])
         let rest = r['rest']
      else
         return s:parseResult(1, res, rest)
      endif
   endwhile
endfunction

" Parses one or more tokens defined by `f`
function! s:parseSome(str, f)
   let res = []
   let rest = a:str
   while v:true
      let r = a:f(rest)
      if r['success']
         let res = add(res, r['parsed'])
         let rest = r['rest']
      else
         return s:parseResult(empty(res) ? 0 : 1, res, rest)
      endif
   endwhile
endfunction

" Parses `fst` first, then if successful parses `snd`
" A result is a success only if both parses are successful
function! s:parseChain(str, fst, snd)
   let a = a:fst(a:str)
   if a['success']
      let b = a:snd(a['rest'])
      if b['success']
         return s:parseResult(1, [a['parsed'], b['parsed']], b['rest'])
      else
         return s:parseResult(0, "", a:str)
      endif
   else
      return s:parseResult(0, "", a:str)
   endif
endfunction

" Same as `parseChain` but a result of `snd` is voided
function! s:parseChainLeft(str, fst, snd)
   let r = s:parseChain(a:str, a:fst, a:snd)
   let r['parsed'] = r['parsed'][0]
   return r
endfunction

" Same as parseChain` but a result of `fst` is voided
function! s:parseChainRight(str, fst, snd)
   let r = s:parseChain(a:str, a:fst, a:snd)
   let r['parsed'] = r['parsed'][1]
   return r
endfunction

" Parses either `fst` or `snd` lazily
" A result is a success only if `fst` or `snd` is successful
function! s:parseAlt(str, fst, snd)
   let r = a:fst(a:str)
   if r['success']
      return s:parseResult(1, r['parsed'], r['rest'])
   else
      let r = a:snd(a:str)
      if r['success']
         return s:parseResult(1, r['parsed'], r['rest'])
      else
         return s:parseResult(0, "", a:str)
      endif
   endif
endfunction

" Same as `parseAlt` but a list of alternatives is provided
function! s:parseAlts(str, alts)
   if empty(a:alts)
      return s:parseResult(0, "", a:str)
   else
      let res = s:parseAlt(a:str, a:alts[0], {str -> s:parseResult(0, "", a:str)})
      if res['success']
         return res
      else
         return s:parseAlts(a:str, a:alts[1:])
      endif
   endif
endfunction

" Parses `f` in parentheses voiding `(` and `)` tokens
function! s:parseInParens(str, f)
   return s:parseChainRight(a:str, {str -> s:parseSymbol(str, '(')},
                            \ {str -> s:parseChainLeft(str,
                              \ {str -> a:f(str)},
                              \ {str -> s:parseSymbol(str, ')')})})
endfunction

" Parses some (1+) `f` seperated by `sep`.
" At least one `f` must be parsed for success
function! s:parseSepBy1(str, f, sep)
   return s:parseChain(a:str, a:f, {str -> s:parseMany(str,
      \ {str -> s:parseChainRight(str, a:sep, a:f)})})
endfunction

" Parses `f` optionally. On failure defaults to
" a successful parse with `def` as a token and the input left unconsumed
function! s:parseOptionWithDefault(str, f, def)
   let r = a:f(a:str)
   if r['success']
      return r
   else
      return s:parseResult(1, a:def, a:str)
   end
endfunction

" Same as `parseOptionWithDefault` but defaults to the empty string
function! s:parseOption(str, f)
   return s:parseOptionWithDefault(a:str, a:f, "")
endfunction

" Same as `parseSepBy1` but the parse is successful even if no `f` is consumed
function! s:parseSepBy(str, f, sep)
   let r = s:parseOptionWithDefault(a:str, {str -> s:parseSepBy1(str, a:f, a:sep)}, [])
   " add the first element, if parsed, to the list of the rest
   return s:mapToken(r, {t -> empty(t) ? [] : ([ t[0] ] + t[1]) })
endfunction

" Parses 0+ whitespace characters
function! s:parseManyWhitespace(str)
   return s:parseMany(a:str, {str -> s:parseSymbol(str, ' ')})
endfunction

" Parses 1+ whitespace characters
function! s:parseSomeWhitespace(str)
   return s:parseSome(a:str, {str -> s:parseSymbol(str, ' ')})
endfunction

" =================================================================

" ======================= Main logic ==============================

" Parses Idris's IDE mode expression (SExp)
function! s:parseResponse(str)
   return s:parseAlts(a:str, [
     \ {str -> s:mapToken(s:parseNatural(str), {x -> str2nr(x)})},
     \ {str -> s:parseString(str)},
     \ {str -> s:parseCommand(str)},
     \ {str -> s:parseInParens(str,
       \ {str -> s:parseSepBy(str, {str -> s:parseResponse(str)}, {str -> s:parseManyWhitespace(str)})})}])
endfunction

" Given a list of filenames
" returns a new list where only files with relative paths are preversed
function! s:filterRelative(filenames)
   if len(a:filenames) == 0
      return []
   else
      let [x; xs] = a:filenames
      if x =~ '\v^/'
         return s:filterRelative(xs)
      else
         return [x] + s:filterRelative(xs)
endfunction

function! s:openByNameIndex(names, index)
   let fullnames = systemlist("fd -p " . a:names[a:index][1] . ' . ' . g:idrisSrcDir)
   let filename = ""
   if len(fullnames) == 0
      echom "Could not find the file in the search path: " . a:names[a:index][1]
      return
   elseif len(fullnames) > 1
      " If there are multiple occurrences, resort to files with relative paths
      let relativeOnly = s:filterRelative(fullnames)
      if len(relativeOnly) > 1 || len(relativeOnly) == 0
         " Can't do anything, report
         " Maybe we should open another fzf window for the user to be able to
         " choose. But this would probably be an overkill
         echom "Multiple files match the input:\n" . join(fullnames, '\n')
         return
      else
         let filename = relativeOnly[0]
      end
   else
      let filename = fullnames[0]
   endif
      silent write
      execute "vsplit " . filename
      call setpos('.', [0, a:names[a:index][2] + 1, a:names[a:index][3] + 1, 0])
      normal! zz
      call execute("vertical resize 50")
endfunction

function! s:openByName(names, str)
   let [_, i, n; rest] = matchlist(a:str, '\v#([0-9]+) \[(.+)\]')
   echom "extracted " . i . " " . n
   call s:openByNameIndex(a:names, i)
endfunction

" Handles any type of response from the IDE socket
function! s:handleResponse(resp)
   if a:resp['success'] && !empty(a:resp['parsed'])
      let p = a:resp['parsed']
      let [cmd, args, id] = p
      if cmd == ":return"
         let [isOk, args] = args
         " id == 2 for NameAt queries
         if id == 2
            if isOk == ":ok"
               if len(args) > 0
                  let names = args
                  let fzfsrc = map(s:zipWithIndex(names[:], 0), '"#" . v:val[0] . " [" . v:val[1][1] . "] " . v:val[1][0]')
                  if len(names) > 1
                     call fzf#run(fzf#wrap({
                            \ 'source' : fzfsrc,
                            \ 'sink' : {file -> s:openByName(names, file)},
                            \ 'down': "~30%"}))
                  else
                     call s:openByNameIndex(names, 0)
                  end
               else
                  echom "No match"
               endif
            else
               call s:WriteIdeResponse("[Client] Error handling `name-at`:\n" . string(args))
            endif
         end

         if isOk == ":error"
            call IWrite("Error:\n" . args)
         end
      elseif cmd == ":write-string"
         call IWrite(args)
      elseif cmd == ":warning"
         call IWrite("Warning:\n" . args[3])
      end
   endif
endfunction

" Prints the response and handles it
function! s:printAndHandleResponse(str)
   let str = a:str
   let len = str2nr(str[0:5], 16)
   let resp = s:slice(str, 6, 6 + len)
   let presp = s:parseResponse(resp)
   " call s:WriteIdeResponse("[Server] " . string({'raw' : str}))
   call s:WriteIdeResponse("[Server] " . string(presp))
   call s:handleResponse(presp)
endfunction

" Handles raw response stream
function! s:handleStream(str, data)
   if !empty(a:data)
      let e = a:data[0]
      if e =~ '\v^[0-9a-fA-F]{6}'
         if a:str != ''
            call s:printAndHandleResponse(a:str)
         endif
         call s:handleStream(e, a:data[1:])
      else
         call s:handleStream(a:str . "\n" . e, a:data[1:])
      end
   else
      if a:str != ''
         call s:printAndHandleResponse(a:str)
      end
   end
endfunction

" Called on every job event (stdout/stderr/exit)
function! s:onSocketEvent(job_id, data, event) dict
    call s:handleStream("", a:data)
endfunction

" Creates the response buffer if absent
function! s:MkIdeResponseWin()
  if (!bufexists("idris-ide-response"))
    let prevBuf = bufnr(@#)
    badd idris-ide-response
    b idris-ide-response
    set buftype=nofile
    b #
    let @# = prevBuf
  endif
endfunction

" Writes `str` to the response buffer
" Ensures that the buffer is actually present
function! s:WriteIdeResponse(str)
   call s:MkIdeResponseWin()
   silent write
   let cwid = bufwinnr('.')
   let rwid = bufwinnr('idris-ide-response')
   if rwid >= 0
      execute(rwid . "wincmd w")
      let resp = split(a:str, '\n')
      call append('$', resp)
      normal! G
      execute(cwid . "wincmd w")
   else
      let save_cursor = getcurpos()
      let prevBuf = @#
      b idris-ide-response
      let resp = split(a:str, '\n')
      call append('$', resp)
      b #
      let @# = prevBuf
      call setpos('.', save_cursor)
   end
endfunction

" IP address of the IDE socket
let g:idrisIdeIp = "0.0.0.0"
" Port of the IDE socket
let g:idrisIdePort = "38398"
" Internal job identifier
let g:idrisIdeSocketId = 0

let g:idrisGetSrcDirCmd = "idris2 --libdir"
let g:idrisGetSrcDirCmdSuffix = "src"

function! s:getSrcDir()
   let libdir = systemlist(g:idrisGetSrcDirCmd)
   if len(libdir) != 1
      echoe "Wrong src dir: " . string(libdir)
      return ""
   else
      return '"' . libdir[0] . "-" . g:idrisGetSrcDirCmdSuffix . '"'
   end
endfunction

let g:idrisSrcDir = s:getSrcDir()

" Establishes a connection with the IDE socket
function! IdrisOpen()
   if g:idrisIdeSocketId == 0
      let g:idrisIdeSocketId = sockconnect("tcp",
                                  \  g:idrisIdeIp . ":" . g:idrisIdePort,
                                  \  {'on_data' : function('s:onSocketEvent'), 'data_buffered' : v:false})
      if g:idrisIdeSocketId > 0
         echom "Connected to Idris2 IDE successfully, IDE socket ID: " . g:idrisIdeSocketId
      endif
   else
      echom "Connection already established"
   end
endfunction

" Encodes and sends the `str` request
function! IdrisSend(str)
   if g:idrisIdeSocketId == 0
      echom "Please establish a connection with an IDE socket first, using `IdrisOpen()`"
   else
      let len = strlen(a:str) + 1
      call chansend(g:idrisIdeSocketId, [printf("%06x", len) . a:str, "\n"])
   end
endfunction

" Sends a request to load the current file
function! IdrisLoadFile()
   write
   call IdrisSend('((:load-file "' . expand("%") . '") 1)')
endfunction

" Sends a request to get the location of the given name,
" afterwards jumps to its definition if found
function! IdrisGoTo(name)
   call IdrisSend('((:name-at "' . a:name . '") 2)')
endfunction

" Closes the connection with the IDE socket
function! IdrisClose()
   call chanclose(g:idrisIdeSocketId)
   let g:idrisIdeSocketId = 0
   echom "Connection with IDE closed"
endfunction

function! s:onIdeJobStdout(jobId, data, _)
   echom "job stdout " . string(a:data)
   if len(a:data) == 2
      " check if the output is probably a port number
      if a:data[0] =~ '\v^[0-9]{2,}'
         call IdrisOpen()
      end
   end
endfunction

function! s:onIdeJobStderr(jobId, data, _)
   call s:WriteIdeResponse("[Server Error] " . string(a:data))
endfunction

function! s:onIdeJobExit(jobId, data, _)
   call IdrisClose()
   let g:idrisIdeJobId = 0
   echom "IDE instance stopped"
endfunction

let s:ideJobCallbacks = {
    \ 'on_stdout': function('s:onIdeJobStdout'),
    \ 'on_stderr': function('s:onIdeJobStderr'),
    \ 'on_exit': function('s:onIdeJobExit')
    \ }

let g:idrisIdeJobId = 0
function! IdrisStartIde()
   if g:idrisIdeJobId == 0
      let g:idrisIdeJobId = jobstart('idris2 --ide-mode-socket 0.0.0.0:' . g:idrisIdePort,
                                   \ extend(s:ideJobCallbacks, {'pty' : v:true}))
   else
      echom "IDE already started"
   end
endfunction

function! IdrisStopIde()
   if g:idrisIdeJobId > 0
      call jobstop(g:idrisIdeJobId)
      let g:idrisIdeJobId = 0
   else
      echom "IDE not yet running"
   end
endfunction

" Start IDE instance
call IdrisStartIde()

function! IdrisGoToSelection()
   let prevX = @x
   normal! "xy
   call IdrisGoTo(@x)
   let @x = prevX
endfunction

" ==============================================================

if !exists('g:idrisIdeDisableDefaultMaps') || !g:idrisIdeDisableDefaultMaps
   " Default maps
   nnoremap <silent> <Leader>K :call IdrisGoTo(expand("\<cword>"))<CR>
   vnoremap <silent> <Leader>K :call IdrisGoToSelection()<CR>
   nnoremap <silent> <Leader>L :call IdrisLoadFile()<CR>
end
