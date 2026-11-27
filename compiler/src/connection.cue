package cases

import "strings"

// Named connection sets: a package declares sets of protocols, each with its
// own connection (its own `Services`, `Hello`, and, if it states them, its own
// encodings). Decision: ComlineProject/core#300, and
// https://comlineproject.github.io/docs/proposals/named-connections/#answers-so-far
//
//   - `@connection = "admin"` on a protocol, or a list
//     (`@connection = ["admin", "public"]`): a protocol may be in several sets.
//   - All or nothing: with no protocol annotated nothing changes. Once one is,
//     every protocol that runs on a connection must be, and `@connection` on a
//     protocol that runs on no connection (the lockstep `datagram`) is an error.
//   - A set's name is lowercase `snake_case`; a keyword of any target and the
//     connection module's own item names (`serve`, `connect`, `accept`,
//     `services`, ...) are refused, with an error that says why.
//   - Each set's encodings are checked on their own. `config.idp` may state a
//     set's own in a top-level `connections` table, defaulting to the package's
//     `wire` and `handshake`. A member's own `@framing` and `@handshake` must
//     agree with its set's, and a protocol in two sets whose framings differ
//     can't pin `@framing`.
//   - Sets need a handshake that compares protocol by protocol: `comline@1` with
//     `datagram@2` can't have sets.
//   - `annotations.connection.allowed = false` forbids the annotation, with no
//     new key.
//
// The codes (`connection::...`) are PROPOSED and wait for the maintainer's
// confirmation (see `compiler/readme.md`).
//
// Every case states the package's `handshake` where it matters, so a default
// (which depends on the protocols' framings) never decides the outcome.

// The setting that lets a protocol say `@framing`.
_cnFraming: "settings = { annotations = { framing = { allowed = true } } }"

// The package's handshake, stated.
_cnComline2: "handshake = \"comline@2\""
_cnComline1: "handshake = \"comline@1\""

// The old wire: `datagram@2` and `comline@1`, which can't have sets.
_cnOldWire: "wire = { framing = \"datagram@2\" }"

// A set in the `connections` table, as `config.idp` writes a dictionary
// (entries separated by whitespace).
_cnSet: {
	name:      string
	framing:   string
	handshake: string
	text:      "    \(name) = { wire = { framing = \"\(framing)\" } handshake = { name = \"\(handshake)\" } }\n"
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
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"list": {
		about: "@connection with a list puts a protocol in several sets"
		packages: app: {
			config: [_cnComline2]
			schemas: api: """
				@connection = ["admin", "public"]
				protocol Health {
				    function ping();
				}

				@connection = "admin"
				protocol Ops {
				    function restart();
				}

				@connection = "public"
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
			schemas: api: (_cnPair & {ops: "@connection = \"admin_api2\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}

	// All or nothing.
	"unassigned": {
		about: "one protocol annotated and another on a connection left out: nothing reaches a connection without a decision (fix: add @connection to Chat)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: ""}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unassigned"]}
	}
	"unassigned-other-schema": {
		about: "all or nothing holds across the package's schemas: a protocol in another schema, left out, is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: {
				admin: "@connection = \"admin\"\nprotocol Ops {\n    function restart();\n}"
				chat:  "protocol Chat {\n    function send();\n}"
			}
		}
		build: "app"
		expect: {builds: false, errors: ["connection::unassigned"]}
	}
	"lockstep-left-out": {
		about: "a lockstep datagram protocol runs on no connection, so it needn't be annotated once others are"
		packages: app: {
			config: [_cnComline2, _cnFraming]
			schemas: api: """
				@connection = "admin"
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
				@connection = "admin"
				protocol Ops {
				    function restart();
				}

				@connection = "admin"
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
			schemas: api: (_cnPair & {ops: "@connection = \"Admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-hyphen": {
		about: "a set's name with a hyphen isn't snake_case and is refused (fix: admin_api)"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"admin-api\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-keyword-rust": {
		about: "a set named like a Rust keyword is refused: it would be a module of that name"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"loop\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-keyword-typescript": {
		about: "a set named like a TypeScript keyword, not a Rust one, is refused too: a keyword of any target"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"interface\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-module-item-serve": {
		about: "a set named serve would collide with the connection module's own serve and is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"serve\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}
	"name-module-item-services": {
		about: "a set named services would collide with the connection module's own services and is refused"
		packages: app: {
			config: [_cnComline2]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"services\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::bad-set-name"]}
	}

	// Sets need a handshake that compares protocol by protocol.
	"old-wire-refused": {
		about: "a set on comline@1 with datagram@2 is refused: a change in one set would refuse every set"
		packages: app: {
			config: [_cnOldWire, _cnComline1]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::needs-per-protocol-handshake"]}
	}
	"table-overrides-old-wire": {
		about: "the check is per set: a package on the old wire can give its sets comline@2 and datagram@3 in the connections table"
		packages: app: {
			config: [_cnOldWire, _cnComline1, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
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
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::needs-per-protocol-handshake"]}
	}
	"table-states-old-wire": {
		about: "a set that states comline@1 with datagram@2 in the table is refused, whatever the package says"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@2", handshake: "comline@1"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::needs-per-protocol-handshake"]}
	}

	// A member's own encodings agree with its set's.
	"member-framing-agrees": {
		about: "a member that pins the framing its set has is fine"
		packages: app: {
			config: [_cnComline2, _cnFraming, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n@framing = \"datagram@3\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"member-framing-disagrees": {
		about: "a member whose @framing isn't its set's is refused (fix: remove @framing, or change the set's)"
		packages: app: {
			config: [_cnComline2, _cnFraming, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n@framing = \"datagram@2\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}
	"member-handshake-disagrees": {
		about: "a member whose @handshake isn't its set's is refused, though it says why it gives the handshake up"
		packages: app: {
			config: [_cnComline2, _allow]
			schemas: api: (_cnPair & {
				ops:  "@connection = \"admin\"\n@handshake = \"none\"\n@unverified = \"the admin console predates Comline\"\n"
				chat: "@connection = \"public\"\n"
			}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}

	// A protocol in two sets.
	"shared-unpinned": {
		about: "a protocol in two sets whose framings differ takes each set's framing, so long as it pins none"
		packages: app: {
			config: [_cnComline2, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@2", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: _cnShared
		}
		build: "app"
		expect: {builds: true, protocols: {Health: given_up: [], Ops: given_up: [], Chat: given_up: []}}
	}
	"shared-pinned-differs": {
		about: "a protocol in two sets whose framings differ can't pin @framing, though it matches one of them (fix: remove @framing)"
		packages: app: {
			config: [_cnComline2, _cnFraming, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@2", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: "@framing = \"datagram@3\"\n" + _cnShared
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}
	"shared-pinned-same": {
		about: "a protocol in two sets whose framings agree may pin the framing they have"
		packages: app: {
			config: [_cnComline2, _cnFraming, (_cnTable & {sets: [
				(_cnSet & {name: "admin", framing: "datagram@3", handshake: "comline@2"}).text,
				(_cnSet & {name: "public", framing: "datagram@3", handshake: "comline@2"}).text,
			]}).text]
			schemas: api: "@framing = \"datagram@3\"\n" + _cnShared
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
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
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
		about: "a set the table states only a format for takes the package's framing: a member pinning it agrees"
		packages: app: {
			config: [_cnOldWire, _cnComline2, _cnFraming, "connections = {\n    admin = { wire = { format = \"json@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n@framing = \"datagram@2\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}
	"table-defaults-mismatch": {
		about: "a set the table states only a format for takes the package's framing, so a member pinning another one is refused"
		packages: app: {
			config: [_cnOldWire, _cnComline2, _cnFraming, "connections = {\n    admin = { wire = { format = \"json@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n@framing = \"datagram@3\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["connection::encoding-mismatch"]}
	}
	"table-format-per-set": {
		about: "each set may state its own format, which is package-wide without sets"
		packages: app: {
			config: [_cnComline2, "connections = {\n    admin = { wire = { format = \"json@1\" } }\n    public = { wire = { format = \"msgpack@1\" } }\n}"]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
		}
		build: "app"
		expect: _cnBuilds
	}

	// Policy.
	"setting-forbids": {
		about: "annotations.connection.allowed = false refuses @connection"
		packages: app: {
			config: [_cnComline2, "settings = { annotations = { connection = { allowed = false } } }"]
			schemas: api: (_cnPair & {ops: "@connection = \"admin\"\n", chat: "@connection = \"public\"\n"}).text
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
	@connection = ["admin", "public"]
	protocol Health {
	    function ping();
	}

	@connection = "admin"
	protocol Ops {
	    function restart();
	}

	@connection = "public"
	protocol Chat {
	    function send();
	}
	"""
