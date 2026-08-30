extends Node

## Autoload. Nodes register themselves here in _ready, so nothing needs a
## hardcoded get_node("A/B/C") chain that breaks on a rename.

var player: Player = null
var dummy: Dummy = null
