package cases

import "strings"

// Named connection sets: a package declares sets of protocols, each with its
// own connection (its own `Services`, `Hello`, and, if it states them, its own
// encodings). Decision: ComlineProject/core#300, and
// https://comlineproject.github.io/docs/proposals/named-connections/#answers-so-far
//
//   - `@connection = admin` on a protocol, or a list
//     (`@connection = [admin, public]`): a protocol may be in several sets.
//   - All or nothing: with no protocol annotated nothing changes. Once one is,
//     every protocol that runs on a connection must be, and `@connection` on a
//     protocol that runs on no connection (the lockstep `datagram`) is an error.
//   - A set is named by a bare identifier, never a string, and its name is
//     lowercase `snake_case` (a name with a hyphen isn't an identifier, so
//     no case writes one); a keyword of any target and the
//     connection module's own item names (`serve`, `connect`, `accept`,
//     `services`, ...) are refused, with an error that says why.
//   - Each set's encodings are checked on their own. `config.idp` may state a
//     set's own in a top-level `connections` table, defaulting to the package's
//     `wire` and `handshake`. A member's own `@handshake` (and `@framing`) must
//     agree with its set's: the handshake's name and its wire parameters
//     (today `exchange`) must match, while its policy parameters (`scope`,
//     `newer_consumer`, `same_version_differs`) may differ per member.
//   - Sets need a handshake that compares protocol by protocol and a framing
//     whose protocol numbers don't depend on position: `comline@2` or later
//     with `datagram@3`. `comline@1` (it hashes the whole schema) with any
//     framing, `datagram@2` (numbers by position) with any handshake, and
//     handshake `none` (no Hello, so nothing enforces the set) are refused.
//     Only `datagram@3` is allowed in a set, so no case can have two sets with
//     different framings, or a member whose framing differs from its set's
//     without also being refused: such disagreements are shown by the
//     handshake's `exchange`, a parameter both ends must agree on.
//   - A list names each set once, and at least one.
//   - `annotations.connection.allowed = false` forbids the annotation, with no
//     new key.
//
// The codes (`connection::...`) are decided, with the reason in the message.

// Every case states the package's `handshake` where it matters, so a default
// (which depends on the protocols' framings) never decides the outcome.

// The setting that lets a protocol say `@framing`.
_cnFraming: "settings = { annotations = { framing = { allowed = true } } }"

// The package's handshake, stated.
_cnComline2: "handshake = \"comline@2\""
_cnComline1: "handshake = \"comline@1\""

// The old wire: `datagram@2` and `comline@1`, which can't have sets (nor can
// either alone).
_cnOldWire: "wire = { framing = \"datagram@2\" }"

// A set in the `connections` table, as `config.idp` writes a dictionary
// (entries separated by whitespace).
_cnSet: {
	name:      string
	framing:   string
	handshake: string
	// The handshake's `exchange`, where the set states one.
	exchange?: string
	_extra:    string | *""
	if exchange != _|_ {_extra: " exchange = \"\(exchange)\""}
	text: "    \(name) = { wire = { framing = \"\(framing)\" } handshake = { name = \"\(handshake)\"\(_extra) } }\n"
}

_cnTable: {
	sets: [...string]
	text: "connections = {\n" + strings.Join(sets, "") + "}"
}


// Two protocols, each in a set of its own, the annotations as given.
_cnPair: {
	ops:  string
	chat: string
	text: "\(ops)protocol Ops {\n    function restart();\n}\n\n\(chat)protocol Chat {\n    function send();\n}"
}

_cnBuilds: {builds: true, protocols: {Ops: given_up: [], Chat: given_up: []}}

groups: connection: {
	// The default: nothing annotated, nothing changes.
	"no-annotation": {
		about: "a package whose protocols carry no @connection builds as before, on the one default connection"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "", chat: ""}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"old-wire-no-annotation": {
		about: "a package on comline@1 and datagram@2 with no @connection is unchanged and builds"
		packages: app: {
			config: [_cnOldWire, _cnComline1]
			schemas: api: (_cnPair & {ops: "", chat: ""}).text
		}
		build: "app"
		expect: _cnBuilds
	}

	// The annotation: one name, a list.
	"one-name": {
		about: "@connection with one name puts each protocol in its own set"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"list": {
		about: "@connection with a list puts a protocol in several sets"
		packages: app: {
			config: [_cnComline2]
			schemas: api: """
				@connection = [admin, public]
				protocol Health {
				    function ping();
				}

				@connection = admin
				protocol Ops {
				    function restart();
				}

				@connection = public
				protocol Chat {
				    function send();
				}
				"""
		}
		build: "app"
		expect: {builds: true, protocols: {Health: given_up: [], Ops: given_up: [], Chat: given_up: []}}
	}
	"name-snake-case": {
		about: "a set's name is lowercase snake_case: letters, digits and underscores"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin_api2\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}

	// All or nothing.
	"unassigned": {
		about: "one protocol annotated and another on a connection left out: nothing reaches a connection without a decision (fix: add @connection to Chat)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: ""}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unassigned"]}
	}
	"unassigned-other-schema": {
		about: "all or nothing holds across the package's schemas: a protocol in another schema, left out, is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: {
				admin: "@connection = admin\nprotocol Ops {\n    function restart();\n}"
				chat:  "protocol Chat {\n    function send();\n}"
			}
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unassigned"]}
	}
	"duplicate-set": {
		about: "a set named twice in one list is refused (fix: name it once)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: """
				@connection = [admin, admin]
				protocol Ops {
				    function restart();
				}

				@connection = public
				protocol Chat {
				    function send();
				}
				"""
		}
		build: "app"
		expect: {builds: false, errors: ["connection::duplicate-set"]}
	}
	"empty-list": {
		about: "an empty list names no set and is refused, not read as a protocol left out (fix: name at least one set)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = []\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::empty-list"]}
	}
	"quoted-name": {
		about: "a set is named by a bare identifier, never a string: @connection = \"admin\" is the annotation value error (core may hint to drop the quotes; the case holds the code only)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["validation::annotation-value-mismatch"]}
	}
	"not-a-name": {
		about: "an annotation value that is neither a name nor a list of names, here a number, is the annotation value error"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = 3\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["validation::annotation-value-mismatch"]}
	}
	"lockstep-left-out": {
		about: "a lockstep datagram protocol runs on no connection, so it needn't be annotated once others are"
		packages: app: {
			config: [_cnComline2, _cnFraming]
			schemas: api: """
				@connection = admin
				protocol Ops {
				    function restart();
				}

				@framing = "datagram"
				@handshake = "comline@1"
				protocol Dump {
				    function put();
				}
				"""
		}
		build: "app"
		expect: {builds: true, protocols: {Ops: given_up: [], Dump: given_up: []}}
	}
	"not-on-a-connection": {
		about: "@connection on a protocol that runs on no connection (the lockstep datagram) is refused"
		packages: app: {
			config: [_cnComline2, _cnFraming]
			schemas: api: """
				@connection = admin
				protocol Ops {
				    function restart();
				}

				@connection = admin
				@framing = "datagram"
				@handshake = "comline@1"
				protocol Dump {
				    function put();
				}
				"""
		}
		build: "app"
		expect: {builds: false, errors: ["connection::not-on-a-connection"]}
	}

	// A set's name.
	"name-uppercase": {
		about: "a set's name that isn't lowercase is refused (fix: admin)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = Admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-keyword-rust": {
		about: "a set named like a Rust keyword is refused: it would be a module of that name"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = loop\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-keyword-typescript": {
		about: "a set named like a TypeScript keyword, not a Rust one, is refused too: a keyword of any target"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = interface\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-module-item-serve": {
		about: "a set named serve would collide with the connection module's own serve and is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = serve\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-module-item-services": {
		about: "a set named services would collide with the connection module's own services and is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = services\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}

	// Sets need a handshake that compares protocol by protocol and a framing
	// that doesn't number protocols by position: comline@2 or later, datagram@3.
	"old-wire-refused": {
		about: "a set on comline@1 with datagram@2 is refused: the handshake hashes the whole schema and the framing numbers by position (the message says both)"
		packages: app: {
			config: [_cnOldWire, _cnComline1]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}
	"comline1-datagram3-refused": {
		about: "a set on comline@1 is refused with any framing, here datagram@3: the handshake hashes the whole schema, so a change in one set would refuse every set (fix: comline@2)"
		packages: app: {
			config: [_cnComline1]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}
	"comline2-datagram2-refused": {
		about: "a set on datagram@2 is refused with any handshake, here comline@2: the framing numbers protocols by position (fix: datagram@3)"
		packages: app: {
			config: [_cnOldWire, _cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}
	"handshake-none-refused": {
		about: "a member with no handshake is refused in a set, though it says why it gives the handshake up: with no Hello nothing enforces the set"
		packages: app: {
			config: [_cnComline2, _allow]
			schemas: api: (_cnPair & {
				ops:  "@connection = admin\n@handshake = \"none\"\n@unverified = \"the admin console predates Comline\"\n"
				chat: "@connection = public\n"
			}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}
	"table-overrides-old-wire": {
		about: "the check is per set: a package on the old wire can give its sets comline@2 and datagram@3 in the connections table, and is no error once every protocol is in a set"
		packages: app: {
			config: [_cnOldWire, _cnComline1, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"table-inherits-old-wire": {
		about: "a set the table doesn't state takes the package's wire and handshake, here the old wire, and is refused"
		packages: app: {
			config: [_cnOldWire, _cnComline1, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}
	"table-states-old-wire": {
		about: "a set that states comline@1 with datagram@2 in the table is refused, whatever the package says"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@2", handshake: "comline@1"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unsupported-encoding"]}
	}

	// A member's own encodings agree with its set's. A set allows one framing
	// (datagram@3), so the disagreement shown is the handshake's `exchange`.
	"member-framing-agrees": {
		about: "a member that pins the framing its set has is fine"
		packages: app: {
			config: [_cnComline2, _cnFraming, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@framing = \"datagram@3\"\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"member-handshake-agrees": {
		about: "a member that writes out the handshake its set has, a default included, is fine"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@handshake = { name = \"comline@2\" , exchange = \"offer\" }\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"member-handshake-policy-differs": {
		about: "a member's @handshake may differ from its set's in a policy parameter (scope, newer_consumer, same_version_differs), which isn't on the wire: only the name and the wire parameters (exchange) must match"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@handshake = { name = \"comline@2\" , scope = \"package\" , newer_consumer = \"refuse\" }\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"member-handshake-disagrees": {
		about: "a member whose @handshake isn't its set's, here another exchange, which both ends must agree on, is refused (fix: remove @handshake, or change the set's)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@handshake = { name = \"comline@2\" , exchange = \"symmetric\" }\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}

	// A protocol in two sets.
	"shared-unpinned": {
		about: "a protocol in two sets whose handshakes differ in exchange takes each set's, so long as it pins none"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2", exchange: "offer"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2", exchange: "symmetric"}).text,
			]}).text]
			schemas: api: _cnShared
		}
		build: "app"
		expect: {builds: true, protocols: {Health: given_up: [], Ops: given_up: [], Chat: given_up: []}}
	}
	"shared-pinned-differs": {
		about: "a protocol in two sets whose handshakes differ can't pin one, though it matches one of the sets (fix: remove @handshake)"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2", exchange: "offer"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2", exchange: "symmetric"}).text,
			]}).text]
			schemas: api: "@handshake = { name = \"comline@2\" , exchange = \"offer\" }\n" + _cnShared
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}
	"shared-pinned-same": {
		about: "a protocol in two sets whose handshakes agree may pin the handshake they have"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: "@handshake = \"comline@2\"\n" + _cnShared
		}
		build: "app"
		expect: {builds: true, protocols: {Health: given_up: [], Ops: given_up: [], Chat: given_up: []}}
	}

	// The `connections` table in config.idp.
	"table-unknown-set": {
		about: "the table names a set no protocol uses (fix: remove the entry, or annotate a protocol)"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "reports", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unknown-set"]}
	}
	"table-without-annotation": {
		about: "with no protocol annotated there are no sets, so any set the table names is unknown"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "", chat: ""}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unknown-set"]}
	}
	"table-defaults-from-package": {
		about: "a set the table states only a format for takes the package's handshake, here exchange symmetric: a member writing it out agrees"
		packages: app: {
			config: ["handshake = { name = \"comline@2\" exchange = \"symmetric\" }", "connections = {\n    admin = { wire = { format = \"json@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@handshake = { name = \"comline@2\" , exchange = \"symmetric\" }\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"table-defaults-mismatch": {
		about: "a set the table states only a format for takes the package's handshake, so a member writing another exchange is refused"
		packages: app: {
			config: ["handshake = { name = \"comline@2\" exchange = \"symmetric\" }", "connections = {\n    admin = { wire = { format = \"json@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = admin\n@handshake = { name = \"comline@2\" , exchange = \"offer\" }\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}
	"table-format-per-set": {
		about: "each set may state its own format, which is package-wide without sets"
		packages: app: {
			config: [_cnComline2, "connections = {\n    admin = { wire = { format = \"json@1\" } }\n    public = { wire = { format = \"msgpack@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}

	// Policy.
	"setting-forbids": {
		about: "annotations.connection.allowed = false refuses @connection"
		packages: app: {
			config: [_cnComline2, "settings = { annotations = { connection = { allowed = false } } }"]
			schemas: api: (_cnPair & {ops: "@connection = admin\n", chat: "@connection = public\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["settings::forbidden"]}
	}
	"setting-forbids-unused": {
		about: "annotations.connection.allowed = false is nothing to a package that never writes @connection"
		packages: app: {
			config: [_cnComline2, "settings = { annotations = { connection = { allowed = false } } }"]
			schemas: api: (_cnPair & {ops: "", chat: ""}).text
		}
		build: "app"
		expect: _cnBuilds
	}
}

// A health check in both sets beside a protocol of each, for the cases whose
// outcome is about a protocol in two sets.
_cnShared: """
	@connection = [admin, public]
	protocol Health {
	    function ping();
	}

	@connection = admin
	protocol Ops {
	    function restart();
	}

	@connection = public
	protocol Chat {
	    function send();
	}
	"""
