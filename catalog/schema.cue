package catalog

import "list"

// What every entry may say about where it stands. `since` is the spec
// version that introduced it, where the changelog names one.
#Lifecycle: {
	status:       *"stable" | "experimental" | "deprecated"
	replaced_by?: string
	since?:       =~"^[0-9]+\\.[0-9]+$"
	if status == "deprecated" {
		replaced_by!: string
	}
}

// Where an `@unverified` marker may sit, outermost to innermost: the
// package, a protocol in it, a function of the protocol, one of its
// arguments, a field of a type, a type.
#Scopes: ["package", "protocol", "function", "argument", "field", "type"]
#Scope: or(#Scopes)

// A guarantee Comline gives between peers, which a protocol can give up
// with `@unverified`. Its id is the name written in `accept_unverified`,
// diagnostics and generated docs.
#Guarantee: close({
	#Lifecycle
	title!:       string
	description!: string
	// What gives it up: the handshake, the format and framing, a handshake
	// policy, or a type.
	comes_from!: "handshake" | "encoding" | "policy" | "type"
	// Where an `@unverified` marker acknowledging it may sit, which follows
	// from where its cause is. In `#Scopes` order, each at most once.
	scopes!: [#Scope, ...#Scope]
})

// A fact an encoding's profile states, with every value it may take and
// what each means. A handshake's facts are booleans: `true` establishes the
// guarantee named in `establishes`.
#Fact: close({
	#Lifecycle
	applies_to!:  "format" | "framing" | "handshake"
	title!:       string
	description!: string
	values!: {[string]: string}
	establishes?: or([for id, _ in guarantees {id}])
})

// An official encoding, by its wire name: the spelling the handshake
// hashes, which never changes.
#Encoding: close({
	#Lifecycle
	kind!:        "format" | "framing" | "handshake"
	title!:       string
	description!: string
	// Other spellings a schema may write, resolved to this name.
	aliases: [...string]
	// The spelling core freezes into the IR, where it isn't the wire name:
	// the one used before the names were versioned.
	frozen_as?: string
	// Whether `profiles/<name>.json` states its facts.
	profile: bool | *true
	// The feature whose vectors prove it.
	feature?: or([for id, _ in features {id}])
	tags: [...string]
})

// A wire feature: a set of vector cases, `vectors/<id>.json`.
#Feature: close({
	#Lifecycle
	title!:       string
	description!: string
})

// Ids, and nothing else, in each kind: a pattern constraint alone would let
// a label that doesn't match through unchecked.
#SnakeId:    "^[a-z][a-z_]*$"
#EncodingId: "^[a-z0-9._-]+(@[0-9]+)?$"
#FeatureId:  "^[a-z0-9-]+$"

guarantees: {[=~#SnakeId]: #Guarantee, [!~#SnakeId]: _|_}
facts: {[=~#SnakeId]: #Fact, [!~#SnakeId]: _|_}
encodings: {[=~#EncodingId]: #Encoding, [!~#EncodingId]: _|_}
features: {[=~#FeatureId]: #Feature, [!~#FeatureId]: _|_}

// A guarantee's scopes follow from where it comes from: what a type gives
// up can be acknowledged on the type, or on whatever uses it, down from the
// protocol; what the handshake, the policies and the encoding give up is
// settled by the package and its protocols, never below a protocol.
_scope_rank: {for i, s in #Scopes {(s): i}}
_scopes_are_ordered: [for id, g in guarantees
	let ranks = [for s in g.scopes {_scope_rank[s]}]
	if len([for i, r in ranks if i > 0 if r <= ranks[i-1] {i}]) > 0 {id}] & []
_scopes_follow_origin: [for id, g in guarantees
	let inner = [for s in g.scopes if _scope_rank[s] >= _scope_rank["function"] {s}]
	if (g.comes_from == "type" && !list.Contains(g.scopes, "type")) || (g.comes_from != "type" && len(inner) > 0) {id}] & []

// A handshake's facts are booleans.
_boolean_handshake_facts: [for id, f in facts if f.applies_to == "handshake" if [for v, _ in f.values {v}] != ["true", "false"] {id}] & []

// An alias names one encoding, and is never another's wire name or frozen
// spelling. A frozen spelling is also an alias.
_spellings: {
	for id, e in encodings for a in e.aliases {(a): id}
}
_aliases_are_unique: list.UniqueItems() & [for id, e in encodings for a in e.aliases {a}]
_aliases_are_not_names: [for a, _ in _spellings if encodings[a] != _|_ {a}] & []
_frozen_is_an_alias: [for id, e in encodings if e.frozen_as != _|_ if !list.Contains(e.aliases, e.frozen_as) {id}] & []

// An official profile, `profiles/<name>.json`: of an encoding the catalog
// gives a profile, and of that encoding's kind. `specs/profile.cue` says the
// rest.
#OfficialProfile: {
	name!: or(sets.profiled)
	kind!: encodings[name].kind
	...
}
