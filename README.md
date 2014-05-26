# PEGParser


PEGParser is a PEG Parser for Julia with Packrat capabilties. PEGParser was inspired by pyparsing, parsimonious, boost::spirit, as well as several others. I was originally writing the EBNF for an entirely different purpose, when it ocurred to me that it wouldn't be too difficult to write a parser. Thus, PEGParsing was born.

## Defining a grammar

To define a grammar you can write:

```julia
@grammar <name> begin
  rule1 = ...
  rule2 = ...
  ...
end
```

### Allowed rules

The following rules can be used:

Terminals: Strings and characters
Or: `a | b | c`
And: `a + b + c`
Grouping: `(a + b) | (c + d)`
One or more: `+((a + b) | (c + d))`
Zero or more: `*((a + b) | (c + d))`
Regular expressions: `r"[a-zA-Z]+"

#### TODO
Multiple: `(a+b)^(3, 5)

## Example 1
Suppose you want a parser that takes input and converts `[text]` into `<b>text<>`. You can write the following grammar:

```julia
@grammar markup begin
  # this is the standard start rule
  start = bold_text

  # compose a sequence
  bold_text = bold_open + text + bold_clode

  # use a regular expression to define the text
  text = r"[a-zA-z]"

  bold_open = '['
  bold_close = ']'
end
```

The first step in using the grammar is to create an AST from a given input:

```julia
(node, pos, error) = parse(markup, "[test]")
```

The variable `node` contains the AST which can be transformed to the desired result. To do so, first a mapping of the node names to transform has to established:

```julia
html = Dict()
html["bold_open"] = (node, children) -> "<b>"
html["bold_close"] = (node, children) -> "</b>"
html["text"] = (node, children) -> node.value
html["bold_text"] = (node, children) -> join(children)
```

And finally:
```julia
result = transform(html, node)
println(result) # "<b>test</b>"
```

## Example 2
Transforms can also be used to calculate a value from the tree. Consider the standard calculator app:

```julia
@grammar calc begin
  start = expr
  number = r"([0-9]+)"
  expr = (term + op1 + expr) | term
  term = (factor + op2 + term) | factor
  factor = number | pfactor
  pfactor = ('(' + expr + ')')
  op1 = '+' | '-'
  op2 = '*' | '/'
end
```

And to use the grammar:

```julia
(node, pos, error) = parse(grammar, "5*(42+3+6+10+2)")

math = Dict()
math["number"] = (node, children) -> float(node.value)
math["expr"] = (node, children) ->
  length(children) == 1 ? children : eval(Expr(:call, children[2], children[1], children[3]))
math["factor"] = (node, children) -> children
math["pfactor"] = (node, children) -> children[2]
math["term"] = (node, children) ->
  length(children) == 1 ? children : eval(Expr(:call, children[2], children[1], children[3]))
math["op1"] = (node, children) -> symbol(node.value)
math["op2"] = (node, children) -> symbol(node.value)

result = transform(math, node)

println(result) # 315.0
```
