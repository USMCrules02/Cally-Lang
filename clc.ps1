<# 
    Cally Lang Interpreter in PowerShell
    This script tokenizes, parses, and evaluates a .clp file.

    Parameters:
      - Switch flags:
            -ast : Outputs the AST (in JSON format).
            -ts  : Outputs the token stream.
	  - args:
			- additional aguments you would want to add on start up
    Usage:
      .\clc.ps1 <Path_To_Your_Program.clp> <args> [-ast] [-ts] <br/>
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
	[Parameter(ValueFromRemainingArguments=$true)]
	$LangArgs,
    [switch]$ast,
    [switch]$ts
)

if (!(Test-Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$sourceLines = Get-Content $FilePath
if (-not $sourceLines) {
    Write-Error "File is empty or cannot be read: $FilePath"
    exit 1
}
$source = $sourceLines -join "`r`n"

$processedLines = foreach ($line in $sourceLines) {
    $line -replace '//.*', ''
}
$source = $processedLines -join "`r`n"

function Tokenize($source) {
    $tokens = @()
    $lines = $source -split "`r?`n"
    $lineCount = $lines.Count
    $symbols = @("(", ")", "{", "}", "[", "]", ";", ",", ".", "+", "-", "*", "/", "%", "=", "<", ">", "!", ":", "$")
    $multiCharOps = @("==", "!=", "<=", ">=", "&&", "||", "++", "--")
    $keywords = @("Main", "if", "else", "while", "for", "print", "input", "parseInt", "len")
    
    for ($i = 0; $i -lt $lineCount; $i++) {
        $lineText = $lines[$i]
        $pos = 0
        $len = $lineText.Length
        while ($pos -lt $len) {
            $char = $lineText[$pos]
            if ([char]::IsWhiteSpace($char)) {
                $pos++
                continue
            }
            if ($char -eq '"') {
                $pos++
                $startPos = $pos
                $str = ""
                while ($pos -lt $len -and $lineText[$pos] -ne '"') {
                    $str += $lineText[$pos]
                    $pos++
                }
                if ($pos -lt $len -and $lineText[$pos] -eq '"') { $pos++ }
                $tokens += [PSCustomObject]@{
                    type        = "String"
                    value       = $str
                    line        = $i + 1
                    columnStart = $startPos
                }
                continue
            }
            if ($char -match '[0-9]') {
                $startPos = $pos
                $num = ""
                while ($pos -lt $len -and $lineText[$pos] -match '[0-9]') {
                    $num += $lineText[$pos]
                    $pos++
                }
                $tokens += [PSCustomObject]@{
                    type        = "Number"
                    value       = [int]$num
                    line        = $i + 1
                    columnStart = $startPos + 1
                }
                continue
            }
            if ($char -match '[A-Za-z_]') {
                $startPos = $pos
                $ident = ""
                while ($pos -lt $len -and $lineText[$pos] -match '[A-Za-z0-9_]') {
                    $ident += $lineText[$pos]
                    $pos++
                }
                if ($keywords -contains $ident) {
                    $tokenType = "Keyword"
                }
                else {
                    $tokenType = "Identifier"
                }
                $tokens += [PSCustomObject]@{
                    type        = $tokenType
                    value       = $ident
                    line        = $i + 1
                    columnStart = $startPos + 1
                }
                continue
            }
            if ($pos + 1 -lt $len) {
                $pair = $lineText.Substring($pos,2)
                if ($multiCharOps -contains $pair) {
                    $tokens += [PSCustomObject]@{
                        type        = "Operator"
                        value       = $pair
                        line        = $i + 1
                        columnStart = $pos + 1
                    }
                    $pos += 2
                    continue
                }
            }
            if ($symbols -contains $char) {
                $tokens += [PSCustomObject]@{
                    type        = "Symbol"
                    value       = $char
                    line        = $i + 1
                    columnStart = $pos + 1
                }
                $pos++
                continue
            }
            Write-Warning "Skipping unknown char '$char' at line $($i + 1), col $($pos + 1)"
            $pos++
        }
    }
    return $tokens
}

$tokens = Tokenize $source

if ($ts) {
    Write-Host "Token Stream:"
    $tokens | ForEach-Object { "[Line $($_.line):Col $($_.columnStart)] $($_.type): $($_.value)" }
}

$global:tokenIndex = 0

function PeekToken() {
    if ($global:tokenIndex -lt $tokens.Count) { return $tokens[$global:tokenIndex] }
    return $null
}

function NextToken() {
    $token = PeekToken
    $global:tokenIndex++
    return $token
}

function ExpectToken($expectedValue) {
    $token = NextToken
    if (-not $token) { throw "Parse Error: Expected '$expectedValue' but reached end of input." }
    if ($token.value -ne $expectedValue) {
        throw ("Parse Error [line {0}, col {1}]: Expected '{2}' but got '{3}'." -f $token.line, $token.columnStart, $expectedValue, $token.value)
    }
    return $token
}

function New-ASTNode($type, $props) {
    $node = @{ type = $type; line = $null; column = $null }
    if ($props.ContainsKey("line"))   { $node.line   = $props["line"] }
    if ($props.ContainsKey("column")) { $node.column = $props["column"] }
    foreach ($key in $props.Keys) {
        if ($key -notin @("type","line","column")) { $node[$key] = $props[$key] }
    }
    return [PSCustomObject]$node
}

function ParseArrayLiteral() {
    $openBracket = NextToken  # Consume "["
    $elements = @()
    while ($true) {
        $peek = PeekToken
        if (-not $peek) { throw "Parse Error: Missing closing ']' for array literal." }
        if ($peek.value -eq "]") { NextToken | Out-Null; break }
        $element = ParseExpression
        $elements += $element
        $peek = PeekToken
        if ($peek -and $peek.value -eq ",") { NextToken | Out-Null; continue }
    }
    return New-ASTNode "ArrayLiteral" @{
        elements = $elements
        line     = $openBracket.line
        column   = $openBracket.columnStart
    }
}

function ParseObjectLiteral() {
    $openBrace = NextToken  # Consume "{"
    $properties = @{}
    while ($true) {
        $peek = PeekToken
        if (-not $peek) { throw "Parse Error: Missing closing '}' for object literal." }
        if ($peek.value -eq "}") { NextToken | Out-Null; break }
        
        # Expect a key (identifier or string)
        if ($peek.type -eq "Identifier" -or $peek.type -eq "String") {
            $keyToken = NextToken
            $key = $keyToken.value
        }
        else {
            throw ("Parse Error [line {0}, col {1}]: Object keys must be identifiers or strings." `
                   -f $peek.line, $peek.columnStart)
        }
        
        $dummy = ExpectToken ":"  # consume colon
        $value = ParseExpression
        $properties[$key] = $value
        
        $peek = PeekToken
        if ($peek -and $peek.value -eq ",") { NextToken | Out-Null; continue }
    }
    return New-ASTNode "ObjectLiteral" @{
        properties = $properties
        line       = $openBrace.line
        column     = $openBrace.columnStart
    }
}

function ParseExpression() {
    $node = ParsePostfix
    while ($true) {
        $token = PeekToken
        if (-not $token) { break }
        if ($token.type -eq "Operator" -or ($token.type -eq "Symbol" -and "+-*/%<>".Contains($token.value))) {
            $op = NextToken
            $right = ParsePostfix 
            $node = New-ASTNode "BinaryOp" @{
                left   = $node
                op     = $op.value
                right  = $right
                line   = $op.line
                column = $op.columnStart
            }
        }
        else { break }
    }
    return $node
}

function ParsePostfix() {
    $node = ParsePrimary
    while ($true) {
        $token = PeekToken
        if (-not $token) { break }
        if ($token.value -eq "[") {
            NextToken | Out-Null  # consume '['
            $indexExpr = ParseExpression
            $dummy = ExpectToken "]"  # capture the closing ']' token
            $node = New-ASTNode "ArrayAccess" @{
                base  = $node
                index = $indexExpr
                line  = $token.line
                column = $token.columnStart
            }
        }
        elseif ($token.value -eq ".") {
            NextToken | Out-Null  # consume '.'
            $propToken = PeekToken
            if (-not $propToken -or ($propToken.type -ne "Identifier" -and $propToken.type -ne "String")) {
                throw ("Parse Error [line {0}, col {1}]: Expected identifier after '.'" -f $token.line, $token.columnStart)
            }
            $prop = NextToken
            $node = New-ASTNode "PropertyAccess" @{
                base     = $node
                property = $prop.value
                line     = $prop.line
                column   = $prop.columnStart
            }
        }
        else {
            break
        }
    }
    return $node
}

function ParsePrimary() {
    $token = PeekToken
    if (-not $token) { throw "Parse Error: Unexpected end of input in expression." }
    
    if ($token.type -eq "Identifier" -and $token.value -eq "p") {
        $next = PeekToken
        $dummy = NextToken  # consume "p"
        $next = PeekToken
        if ($next -and $next.value -eq "{") {
            return ParsePSBlock
        }
        else {
            return New-ASTNode "Variable" @{
                name = "p"
                line = $token.line
                column = $token.columnStart
            }
        }
    }
    
    switch ($token.type) {
        "Number" {
            NextToken | Out-Null
            return New-ASTNode "Number" @{
                value  = $token.value
                line   = $token.line
                column = $token.columnStart
            }
        }
        "String" {
            NextToken | Out-Null
            return New-ASTNode "String" @{
                value  = $token.value
                line   = $token.line
                column = $token.columnStart
            }
        }
        "Identifier" {
            $identToken = NextToken
            $varNode = New-ASTNode "Variable" @{
                name   = $identToken.value
                line   = $identToken.line
                column = $identToken.columnStart
            }
            $next = PeekToken
            if ($next -and $next.type -eq "Operator" -and ($next.value -in @("++", "--"))) {
                $opToken = NextToken
                return New-ASTNode "UnaryOp" @{
                    op     = $opToken.value
                    value  = $varNode
                    line   = $opToken.line
                    column = $opToken.columnStart
                }
            }
            return $varNode
        }
        "Keyword" {
            $kwToken = NextToken
            if ($kwToken.value -in @("if", "while", "for")) {
                throw ("Parse Error [line {0}, col {1}]: Unexpected keyword '{2}' in expression." `
                       -f $kwToken.line, $kwToken.columnStart, $kwToken.value)
            }
            $next = PeekToken
            if ($next -and $next.value -eq "(") {
                NextToken | Out-Null
                $args = @()
                while ($true) {
                    $next = PeekToken
                    if (-not $next) { throw "Parse Error: Missing closing ')' after $($kwToken.value)(...)" }
                    if ($next.value -eq ")") { NextToken | Out-Null; break }
                    $arg = ParseExpression
                    $args += $arg
                    $next = PeekToken
                    if ($next -and $next.value -eq ",") { NextToken | Out-Null; continue }
                }
                return New-ASTNode "FuncCall" @{
                    name   = $kwToken.value
                    args   = $args
                    line   = $kwToken.line
                    column = $kwToken.columnStart
                }
            }
            else {
                return New-ASTNode "Variable" @{
                    name   = $kwToken.value
                    line   = $kwToken.line
                    column = $kwToken.columnStart
                }
            }
        }
        default {
            if ($token.value -eq "(") {
                NextToken | Out-Null
                $expr = ParseExpression
                $dummy = ExpectToken ")"
                return $expr
            }
            elseif ($token.value -eq "[") {
                return ParseArrayLiteral
            }
            elseif ($token.value -eq "{") {
                return ParseObjectLiteral
            }
            else {
                throw ("Parse Error [line {0}, col {1}]: Unexpected token '{2}' ({3})." `
                       -f $token.line, $token.columnStart, $token.value, $token.type)
            }
        }
    }
}

function ParseStatement() {
    while ($true) {
        $temp = PeekToken
        if (-not $temp) { break }
        if ($temp.value -eq ";") {
            NextToken | Out-Null
        }
        else {
            break
        }
    }
    $token = PeekToken
    if (-not $token) { return $null }
    if ($token.type -eq "Keyword") {
        switch ($token.value) {
            "if"    { return ParseIfStatement }
            "while" { return ParseWhileStatement }
            "for"   { return ParseForStatement }
        }
    }
    $expr = ParseExpression
    $next = PeekToken
    if ($next -and $next.value -eq "=") {
        NextToken | Out-Null
        $valExpr = ParseExpression
        $semi = PeekToken
        if (-not $semi -or $semi.value -ne ";") {
            throw ("Parse Error [line {0}, col {1}]: Missing semicolon ';' after assignment statement." -f $valExpr.line, $valExpr.column)
        }
        NextToken | Out-Null
        return New-ASTNode "Assignment" @{
            variable = $expr
            value    = $valExpr
            line     = $expr.line
            column   = $expr.column
        }
    }
    else {
        $semi = PeekToken
        if (-not $semi -or $semi.value -ne ";") {
            throw ("Parse Error [line {0}, col {1}]: Missing semicolon ';' after expression statement." -f $expr.line, $expr.column)
        }
        NextToken | Out-Null
        return New-ASTNode "ExprStmt" @{
            expression = $expr
            line       = $expr.line
            column     = $expr.column
        }
    }
}

function ParsePSBlock() {
    $openBrace = NextToken  # consume '{'
    $rawCode = ""
    $braceCount = 1
    # Define symbols that should be concatenated with no extra space.
    $noSpaceSymbols = @("(", ")", "{", "}", "[", "]", "$", ".", ",", ";", ":", "+", "-", "*", "/", "%", "=", "<", ">", "!", "++", "--")
    while ($braceCount -gt 0) {
        $token = NextToken
        if (-not $token) { throw "Parse Error: Missing closing '}' for PS block." }
        if ($token.value -eq "{") {
            $braceCount++
        }
        elseif ($token.value -eq "}") {
            $braceCount--
            if ($braceCount -eq 0) { break }
        }
        # Append token.value without extra space if token is in the no-space list; otherwise add a space.
        if ($noSpaceSymbols -contains $token.value) {
            $rawCode += $token.value
        }
        else {
            $rawCode += $token.value + " "
        }
    }
    $rawCode = $rawCode.Trim()
    return New-ASTNode "PSBlock" @{
        code   = $rawCode
        line   = $openBrace.line
        column = $openBrace.columnStart
    }
}

function ParseBlock() {
    $openBrace = PeekToken
    if (-not $openBrace -or $openBrace.value -ne "{") {
        throw ("Parse Error [line {0}, col {1}]: Expected '{{' but got '{2}'." -f $openBrace.line, $openBrace.columnStart, $openBrace.value)
    }
    NextToken | Out-Null
    $stmts = @()
    while ($true) {
        $token = PeekToken
        if (-not $token) { throw "Parse Error: Missing closing '}' for block." }
        if ($token.value -eq "}") {
            NextToken | Out-Null
            break
        }
        $stmt = ParseStatement
        if ($stmt) { $stmts += $stmt }
    }
    return $stmts
}

function ParseIfStatement() {
    $ifToken = NextToken
    $dummy = ExpectToken "("
    $condition = ParseExpression
    $dummy = ExpectToken ")"
    $thenBlock = ParseBlock
    $elseBlock = @()
    $next = PeekToken
    if ($next -and $next.type -eq "Keyword" -and $next.value -eq "else") {
        NextToken | Out-Null
        $elseBlock = ParseBlock
    }
    return New-ASTNode "If" @{
        condition = $condition
        then      = $thenBlock
        else      = $elseBlock
        line      = $ifToken.line
        column    = $ifToken.columnStart
    }
}

function ParseWhileStatement() {
    $whileToken = NextToken
    $dummy = ExpectToken "("
    $condition = ParseExpression
    $dummy = ExpectToken ")"
    $body = ParseBlock
    return New-ASTNode "While" @{
        condition = $condition
        body      = $body
        line      = $whileToken.line
        column    = $whileToken.columnStart
    }
}

function ParseForStatement() {
    $forToken = NextToken
    $dummy = ExpectToken "("
    $init = $null
    $peek = PeekToken
    if ($peek -and $peek.value -ne ";") {
        $lhs = ParseExpression
        $maybeEq = PeekToken
        if ($maybeEq -and $maybeEq.value -eq "=") {
            NextToken | Out-Null
            $rhs = ParseExpression
            $init = New-ASTNode "Assignment" @{
                variable = $lhs
                value    = $rhs
                line     = $lhs.line
                column   = $lhs.column
            }
        }
        else {
            # Wrap the raw expression in an ExprStmt so it is recognized later.
            $init = New-ASTNode "ExprStmt" @{
                expression = $lhs
                line       = $lhs.line
                column     = $lhs.column
            }
        }
    }
    $dummy = ExpectToken ";"
    $condition = $null
    $peek = PeekToken
    if ($peek -and $peek.value -ne ";") {
        $condition = ParseExpression
    }
    $dummy = ExpectToken ";"
    $update = $null
    $peek = PeekToken
    if ($peek -and $peek.value -ne ")") {
        $update = ParseExpression
    }
    $dummy = ExpectToken ")"
    $body = ParseBlock
    return New-ASTNode "For" @{
        init      = $init
        condition = $condition
        update    = $update
        body      = $body
        line      = $forToken.line
        column    = $forToken.columnStart
    }
}

function ParseProgram() {
    $token = NextToken
    if (-not $token -or $token.value -ne "Main") {
        $line = if ($token) { $token.line } else { "-" }
        $col  = if ($token) { $token.columnStart } else { "-" }
        throw ("Program must start with 'Main'. Found '{0}' at line {1}, col {2}." -f ($token.value), $line, $col)
    }

    # Check if the next token is "(" to parse parameters.
    $next = PeekToken
    if ($next -and $next.value -eq "(") {
        $dummy = ExpectToken "("
        $paramToken = NextToken
		$global:Env[$paramToken.value] = $LangArgs  
        if (-not $paramToken) { throw "Parse Error: Missing parameter in Main(...)" }
        $dummy = ExpectToken ")"
    }
    
    $body = ParseBlock
    if (PeekToken -ne $null) {
        throw "Parse Error: Extra tokens remain in the input."
    }
    return New-ASTNode "Program" @{ body = $body; line = $token.line; column = $token.columnStart }
}

$programAST = ParseProgram

if ($ast) {  
    Write-Host "AST:"
    $programAST | ConvertTo-Json -Depth 10 | Write-Host
}

function Builtin_print {
	param(
	$printv, 
	$type
	)
    $output = ""
    foreach ($p in $printv) {
        # Check if the value is an array or a hashtable (object)
        if ($p -is [array] -or $p -is [hashtable]) {
            # Convert to a JSON-like string
            $processed = $p | ConvertTo-Json -Compress
        }
		# Replace literal "\n" with an actual newline if needed
		$processed = $p -replace '\\n', "`n"
        $output += $processed
    }
    Write-Host -NoNewline $output
    return $null
}

# Aparently the only way to remove the colon from Read-Host prompts is to overide it :( 
function Read-Host($prompt) {
  Write-Host "$prompt" -NoNewline
  Microsoft.PowerShell.Utility\Read-Host
}
function Builtin_input($printv) {
    return Read-Host $printv[0]
}

function Builtin_len {
	param(
	$len, 
	$type
	)
    if ($len.Count -ge 1) {
        if ($type -eq [string]) { 
			$arg = [string]$len
			return $arg.Length 
		}
        elseif ($type -is [object]) { return $len.Count }
    }
    return 0
}

$global:BuiltinFuncs = @{
    "print"    = { param($value, $type) Builtin_print $value $type}
    "input"    = { param($value, $ignored = $null) Builtin_input $value }
    "len"      = { param($value, $type) Builtin_len $value $type }
}

function EvalExpression($node) {
    if (-not $node) { return $null }
    switch ($node.type) {
        "Number"  { return $node.value }
        "String"  { return $node.value }
        "Variable" {
            $n = $node.name
            if ($global:Env.ContainsKey($n)) { return $global:Env[$n] }
            else {
                throw ("Runtime Error [line {0}, col {1}]: Variable '{2}' not defined." -f $node.line, $node.column, $n)
            }
        }
		"PSBlock" {
			$code = $node.code.Trim()
			
			foreach ($key in $global:Env.Keys) {
				 $pattern = "\$\{\{\s*$key\s*\}\}"
				 $replacement = $global:Env[$key].ToString()
				 $code = $code -replace $pattern, $replacement
			}
			
			if ($code -notmatch '\breturn\b') {
				 $code = $code + "; return $null"
			}
			
			$sb = [scriptblock]::Create($code)
			$result = & $sb
			return $result
		}
		"ArrayAccess" {
			$baseValue = EvalExpression $node.base
			$indexValue = EvalExpression $node.index
			# If the base value is a string, convert the indexed char to a string.
			if ($baseValue -is [string]) {
				return [string]$baseValue[$indexValue]
			}
			else {
				return $baseValue[$indexValue]
			}
		}
        "PropertyAccess" {
            $baseValue = EvalExpression $node.base
            $propName = $node.property
            return $baseValue[$propName]
        }
        "BinaryOp" {
            $l = EvalExpression $node.left
            $r = EvalExpression $node.right
            switch ($node.op) {
                "+"  { return $l + $r }
                "-"  { return $l - $r }
                "*"  { return $l * $r }
                "/"  {
                    if ($r -eq 0) {
                        throw ("Runtime Error [line {0}, col {1}]: Division by zero." -f $node.line, $node.column)
                    }
                    return [int]($l / $r)
                }
                "%"  { return $l % $r }
                "==" { return ($l -eq $r) }
                "!=" { return ($l -ne $r) }
                "<"  { return ($l -lt $r) }
                "<=" { return ($l -le $r) }
                ">"  { return ($l -gt $r) }
                ">=" { return ($l -ge $r) }
                default {
                    throw ("Runtime Error [line {0}, col {1}]: Unsupported operator '{2}'" -f $node.line, $node.column, $node.op)
                }
            }
        }
        "UnaryOp" {
            $val = EvalExpression $node.value
            switch ($node.op) {
                "++" { 
                    $global:Env[$node.value.name] = [int]$val + 1
                    return $val 
                }
                "--" { 
                    $global:Env[$node.value.name] = [int]$val - 1
                    return $val 
                }
                default {
                    throw ("Runtime Error [line {0}, col {1}]: Unsupported operator '{2}'" -f $node.line, $node.column, $node.op)
                }
            }
        }
		"FuncCall" {
			$fname = $node.name
			$vals = @()
			foreach ($a in $node.args) { 
				 $vals += EvalExpression $a 
			}
			if ($fname -eq "len") {
				 if (($vals.Count -eq 1) -and ($vals[0] -ne $null)) {
					 $typeName = $vals[0].GetType().Name

				 } else {
					 throw "len expects one argument."
				 }
				 return & $global:BuiltinFuncs[$fname] $vals[0] $typeName
			}
			else {
				 return & $global:BuiltinFuncs[$fname] $vals
			}
		}
        "ArrayLiteral" {
            $result = @()
            foreach ($element in $node.elements) {
                $result += EvalExpression $element
            }
            return $result
        }
        "ObjectLiteral" {
            $result = @{}
            foreach ($key in $node.properties.Keys) {
                $result[$key] = EvalExpression $node.properties[$key]
            }
            return $result
        }
        default {
            throw ("Runtime Error [line {0}, col {1}]: Unknown expression type: {2}" -f ($node.line -or "-"), ($node.column -or "-"), $node.type)
        }
    }
}

function EvalStatement($node) {
    if (-not $node -or -not $node.type) { return $null }
    switch ($node.type) {
        "Assignment" {
            $varNode = $node.variable
            if ($varNode.type -ne "Variable") {
                throw ("Runtime Error [line {0}, col {1}]: Invalid left-hand side in assignment; expected variable but found '{2}'." -f $node.line, $node.column, $varNode.type)
            }
            $vName = $varNode.name
            $value = EvalExpression $node.value
            $global:Env[$vName] = $value
            return $null
        }
        "ExprStmt" {
            EvalExpression $node.expression | Out-Null
            return $null
        }
        "If" {
            if (EvalExpression $node.condition) { EvalBlock $node.then }
            else { EvalBlock $node.else }
            return $null
        }
        "While" {
            while (EvalExpression $node.condition) {
                EvalBlock $node.body
            }
            return $null
        }
        "For" {
            EvalStatement $node.init | Out-Null
            while (EvalExpression $node.condition) {
                EvalBlock $node.body
                EvalExpression $node.update | Out-Null
            }
            return $null
        }
        default {
            throw ("Runtime Error [line {0}, col {1}]: Unknown statement type: {2}" -f $node.line, $node.column, $node.type)
        }
    }
}

function EvalBlock($stmts) {
    foreach ($s in $stmts) {
        if ($null -eq $s) { continue }
        EvalStatement $s
    }
}

try {
    EvalBlock $programAST.body
} catch {
    Write-Error $_
}
