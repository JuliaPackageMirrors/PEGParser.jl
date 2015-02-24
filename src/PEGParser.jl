module PEGParser

import Base: show, parse

# include("EBNF.jl")
include("rules.jl")
# include("Node.jl")


export parse, ParseError, MatchRule, Node, transform, Grammar, Rule
export @grammar

immutable ParseError
  msg::String
  pos::Int64
end

type MatchRule{T} end

abstract ParserCache

type DefaultCache <: ParserCache
  values::Dict{String, Node}
end

function parse(grammar::Grammar, text::String; cache=nothing, start=:start)
  rule = grammar.rules[start]
  (ast, pos, error) = parse(grammar, rule, text, 1, cache)

  if pos < length(text) + 1
    error = ParseError("Entire string did not match", pos)
  end

  return (ast, pos, error)
end

function transform(fn::Function, node::Node)
  return transform(fn, node)
end

isleaf(node::Node) = isempty(node.children)

function transform(fn::Function, node::Node)
  transformed = [transform(fn, child) for child in node.children]

  if method_exists(fn, (Node, Any, MatchRule{node.sym}))
    label = MatchRule{node.sym}()
  else
    label = MatchRule{:default}()
  end

  return fn(node, transformed, label)
end

unref{T <: Any}(value::T) = value
unref{T <: Rule}(node::Node, ::Type{T}) = node
unref(node::Node, ::Type{ReferencedRule}) = node.children[1]
unref(node::Node) = unref(node, node.ruleType)

function parse(grammar::Grammar, rule::Rule, text::String, pos::Int64, cache::Nothing = nothing)
  return uncached_parse(grammar, rule, text, pos, cache)
end

function parse(grammar::Grammar, rule::Rule, text::String, pos::Int64, cache::DefaultCache)
  cachekey::String = "$(object_id(rule))$pos"
  if haskey(cache.values, cachekey)
    cachedresult = cache.values[cachekey]
    (node, pos, error) = (cachedresult, cachedresult.last, nothing)
  else
    (node, pos, error) = uncached_parse(grammar, rule, text, pos, cache)

    # store in cache if we got back a match
    if node !== nothing
      cache.values[cachekey] = node
    end
  end

  return (node, pos, error)
end

function make_node(rule, value, first, last, children)
  # return rule.action(rule, value, first, last, children)
  # return (rule, value, first, last, children) -> rule.action()
  # println("children = $children")
  # return
  value = rule.action(rule, value, first, last, children)
  # println("\tvalue = $value")
  return value
end

function uncached_parse(grammar::Grammar, rule::ReferencedRule, text::String, pos::Int64, cache)
  refrule = grammar.rules[rule.symbol]

  firstPos = pos
  (childNode, pos, error) = parse(grammar, refrule, text, pos, cache)

  println("rule = $(rule.name)")
  if childNode !== nothing
    # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, [childNode], typeof(rule))
    node = make_node(rule, text[firstPos:pos-1], firstPos, pos, [childNode])
    return (node, pos, error)
    # return (rule.action(node), pos, error)
  else
    return (nothing, pos, error)
  end
end

function uncached_parse(grammar::Grammar, rule::OrRule, text::String, pos::Int64, cache)
  # Try branches in order (left to right). The first branch to match will be marked
  # as a success. If no branches match, then return an error.
  firstPos = pos
  for branch in rule.values
    (child, pos, error) = parse(grammar, branch, text, pos, cache)

    if child !== nothing
      # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, [unref(child)], typeof(rule))
      node = make_node(rule, text[firstPos:pos-1], firstPos, pos, [unref(child)])
      return (node, pos, error)
    end
  end

  # give error
  return (nothing, pos, ParseError("No matching branches", pos))
end

function uncached_parse(grammar::Grammar, rule::AndRule, text::String, pos::Int64, cache)
  firstPos = pos;

  # All items in sequence must match, otherwise give an error
  value = {}
  for item in rule.values
    (child, pos, error) = parse(grammar, item, text, pos, cache)

    # check for error
    if error !== nothing
      return (nothing, firstPos, error)
    end

    if child !== nothing
      push!(value, unref(child))
    end
  end

  # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, value, typeof(rule))
  # println("make_node($rule, $(text[firstPos:pos-1]), $firstPos, $pos, $value)")
  node = make_node(rule, text[firstPos:pos-1], firstPos, pos, value)
  # println("rule.action = $(rule.action)")
  return (node, pos, nothing)
end

# TODO: there should be string functions that already do this
function string_matches(expected::Char, actual::String, first::Int64, last::Int64)
  if first > length(actual)
    return false
  end

  return char(actual[first]) == expected;
end

function string_matches(expected::String, actual::String, first::Int64, last::Int64)
  if last - 1 > length(actual)
    return false;
  end

  return expected == actual[first:last-1];
end

function uncached_parse(grammar::Grammar, rule::Terminal, text::String, pos::Int64, cache)
  local size::Int64 = length(rule.value)

  if string_matches(rule.value, text, pos, pos+size)
    size = length(rule.value)
    # node = Node(rule.name, text[pos:pos+size-1], pos, pos+size, [], typeof(rule))
    node = make_node(rule, text[pos:pos+size-1], pos, pos+size, [])
    return (unref(node), pos+size, nothing)
  end

  len = min(pos+length(rule.value)-1, length(text))
  return (nothing, pos, ParseError("'$(text[pos:len])' does not match '$(rule.value)'.", pos))
end

# TODO: look into making this more streamlined
function uncached_parse(grammar::Grammar, rule::OneOrMoreRule, text::String, pos::Int64, cache)
  firstPos = pos
  (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

  # make sure there is at least one
  if child === nothing
    return (nothing, pos, ParseError("No match (OneOrMoreRule)", pos))
  end

  # and continue making matches for as long as we can
  children = {unref(child)}
  while error == nothing
    (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

    if error === nothing && child !== nothing
      push!(children, unref(child))
    end
  end

  # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, children, typeof(rule))
  node = make_node(rule, text[firstPos:pos-1], firstPos, pos, children)
  return (node, pos, nothing)
end

function uncached_parse(grammar::Grammar, rule::ZeroOrMoreRule, text::String, pos::Int64, cache)
  firstPos::Int64 = pos
  children::Array{Node} = {}

  error = nothing
  while error == nothing
    # FIXME: this was an error and now untested
    (child, pos, error) = parse(grammar, rule.value, text, pos, cache)

    if error === nothing && child !== nothing
      push!(children, unref(child))
    end
  end

  if length(children) > 0
    # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, children, typeof(rule))
    node = make_node(rule, text[firstPos:pos-1], firstPos, pos, children)
  else
    node = nothing
  end

  return (node, pos, nothing)
end

function uncached_parse(grammar::Grammar, rule::RegexRule, text::String, pos::Int64, cache)
  firstPos = pos;

  # use regex match
  if ismatch(rule.value, text[firstPos:end])
    value = match(rule.value, text[firstPos:end])

    if length(value.match) == 0
      # this means that we didn't match, but the regex was optional, so we don't want to give an
      # error
      return (nothing, firstPos, nothing)
    else
      pos += length(value.match)
      node = make_node(rule, text[firstPos:pos-1], firstPos, pos, [])
      # node = unref(Node(rule.name, text[firstPos:pos-1], firstPos, pos, [], typeof(rule)))

      # println("....")
      # tnode = rule.action(node)
      # println("----")

      return (unref(node), pos, nothing)
    end
  else
    return (nothing, firstPos, ParseError("Could not match RegEx", pos))
  end
end

function uncached_parse(grammar::Grammar, rule::OptionalRule, text::String, pos::Int64, cache)
  (child, pos, error) = parse(grammar, rule.value, text, pos, cache)
  firstPos = pos

  if child !== nothing
    # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, [unref(child)], typeof(rule))
    node = make_node(rule, text[firstPos:pos-1], firstPos, pos, [unref(child)])
    return (unref(node), pos, error)
  end

  # no error, but we also don't move the position or return a valid node
  return (nothing, firstPos, nothing)
end

function uncached_parse(grammar::Grammar, rule::ListRule, text::String, pos::Int64, cache)
  firstPos = pos

  # number of occurances
  count = 0

  error = nothing
  children = {}

  # continue making matches for as long as we can
  while error === nothing
    (child, pos, error) = parse(grammar, rule.entry, text, pos, cache)

    if child !== nothing
      push!(children, unref(child))
      (dchild, pos, error) = parse(grammar, rule.delim, text, pos, cache)
    else
      break
    end

    count += 1
  end

  if count < rule.min
    return (nothing, pos, ParseError("No match (ListRule)", pos))
  end

  # node = Node(rule.name, text[firstPos:pos-1], firstPos, pos, children, typeof(rule))
  node = make_node(rule, text[firstPos:pos-1], firstPos, pos, children)
  return (node, pos, nothing)
end

function uncached_parse(grammar::Grammar, rule::SuppressRule, text::String, pos::Int64, cache)
  # use rule contained in the SuppressRule to parse, but don't return anything
  (_, pos, error) = uncached_parse(grammar, rule.value, text, pos, cache)
  return (nothing, pos, error)
end

# function uncached_parse(grammar::Grammar, rule::SemanticActionRule, text::String, pos::Int64, cache)
#   firstPos = pos
#   (ast, pos, error) = uncached_parse(grammar, rule.rule, text, pos, cache)
#
#   if ast !== nothing
#     # if typeof(rule.action) === Int64
#     #   child = ast.children[rule.selection]
#     #   node = Node(ast.name, child.value, child.first, child.last, child.children, child.ruleType)
#     #   return (node, pos, error)
#     # elseif typeof(rule.selection) === Function
#     #   node = rule.selection(ast)
#     #   return (node, pos, error)
#     # end
#     node = rule.action(ast)
#     return (node, pos, error)
#   end
#
#   return (nothing, pos, error)
# end

end
