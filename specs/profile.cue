package conformance

import "github.com/comlineproject/specification/catalog"

// `profiles/<name>.json`: facts about how an encoding encodes, each naming
// the vector cases that prove it. Which facts each kind states, and the
// values each may take, are the catalog's (`catalog/facts.cue`).
#Profile: #FormatProfile | #FramingProfile | #HandshakeProfile

// A format states every fact. It may also state how many bytes each kind of
// value takes (`sizes`, `catalog/schema.cue`): an official format's are the
// catalog's, which `specs/check.sh` holds the profile to; a custom format
// without them has no size, and nothing guesses one.
#FormatProfile: close({
	$schema?: string
	name!:    #ProfileName
	kind!:    "format"
	facts!: close({
		for id, fact in catalog.facts if fact.applies_to == "format" {
			(id)!: close({value!: or([for v, _ in fact.values {v}]), proven_by!: #ProvenBy})
		}
	})
	sizes?: catalog.#Sizes
})

// A framing states every fact.
#FramingProfile: close({
	$schema?: string
	name!:    #ProfileName
	kind!:    "framing"
	facts!: close({
		for id, fact in catalog.facts if fact.applies_to == "framing" {
			(id)!: close({value!: or([for v, _ in fact.values {v}]), proven_by!: #ProvenBy})
		}
	})
})

// A handshake may leave a fact that establishes a guarantee out, which reads
// as `false`: not established, and one that has a default (`schema_comparison`:
// `whole_schema`), which reads as the default. Any other fact it states, as a
// framing does.
#HandshakeProfile: close({
	$schema?: string
	name!:    #ProfileName
	kind!:    "handshake"
	facts!: close({
		for id, fact in catalog.facts if fact.applies_to == "handshake" {
			if fact.establishes != _|_ {(id)?: #Agreement}
			if fact.establishes == _|_ if fact.default != _|_ {(id)?: close({value!: or([for v, _ in fact.values {v}]), proven_by!: #ProvenBy})}
			if fact.establishes == _|_ if fact.default == _|_ {(id)!: close({value!: or([for v, _ in fact.values {v}]), proven_by!: #ProvenBy})}
		}
	})
})

// The cases that prove a fact.
#ProvenBy: [#CaseId, ...#CaseId]

// `true` needs the cases that show it; `false` claims nothing.
#Agreement:
	close({value!: true, proven_by!: #ProvenBy}) |
	close({value!: false, proven_by?: []})
