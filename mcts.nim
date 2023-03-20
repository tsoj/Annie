import
    types,
    position,
    positionUtils,
    search,
    move

import std/[
    options
]


type Node = object
    lastMove: Move
    position: Position
    rollouts: int
    value: Value
    children: Option[seq[Node]]

func rollout*(position: Position, state: var SearchState): Value =
    position.search(state, 4.Ply)

func explore(node: var Node, state: var SearchState) =
    if node.children.isNone:
        let 
        node.children = some()

