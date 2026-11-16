package cases

// How a type is named once it is imported. A qualified reference starts with
// a name a `use` brought into scope, as in Rust, or with a root (`package`,
// `parent`, `self`, `std`, a dependency). Rule and decision:
// https://comlineproject.github.io/docs/proposals/use-paths-and-groups/relative-use/#qualified-references
//
//   - A whole-namespace `use` brings in only its name: after
//     `use package::types`, `types::User` is the way to write it, and a bare
//     `User` is `reference::not-in-scope`. Fix: add `use package::types::User`,
//     or write `types::User`.
//   - A `use` of an item, `{ ... }` or `*` brings in the names it lists: after
//     `use package::types::User`, a bare `User` and not `types::User`, which is
//     `reference::qualifier-not-in-scope`. Fix: write `User`.
//   - A full path works in a type position with no `use`: `package::`,
//     `parent::`, `self::`, `std::` and a dependency's name are roots.
//   - A path goes down from a name in scope: `billing::api::Invoice` after
//     `use package::billing`.
//   - A qualified reference is frozen as its resolved path, so each way of
//     writing one reaches the same type. The cases can't read the frozen IR,
//     so they show it by what each spelling reaches: a decoy `Invoice` in
//     another schema holds an unbounded string, and the one reached holds a
//     bounded one, which the protocol using it gives up nothing for.
//
// A refused reference is an error at once, with the likely rewrite as its
// fix. The fix isn't part of what a case holds a compiler to (a diagnostic is
// matched on its code and severity); it is in each case's description.

_refTypes: """
	struct User {
	    id: u32
	}

	struct Order {
	    id: u32
	}
	"""

// A schema holding `User` as a field, whichever way the type is written.
_refHolder: {
	_ref: string
	text: "struct Account {\n    owner: \(_ref)\n}"
}

// A protocol using an `Invoice`, which is bounded only when it is the one in
// `billing/api`.
_refOrders: {
	_ref: string
	text: "protocol Orders {\n    function send(i: \(_ref));\n}"
}

_refBilling: """
	struct Invoice {
	    data: char[max 64]
	}
	"""

// The decoy: another `Invoice`, in a schema that sorts before `billing`.
_refArchive: """
	struct Invoice {
	    data: string
	}
	"""

_refGreeting: """
	struct Greeting {
	    text: char[max 64]
	}
	"""

groups: references: {
	// A whole-namespace `use` brings in only its name.
	"namespace-qualified": {
		about: "after use package::types, types::User reaches the item"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types\n\n" + (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"namespace-bare-refused": {
		about: "after use package::types a bare User is not in scope (fix: add use package::types::User, or write types::User)"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types\n\n" + (_refHolder & {_ref: "User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::not-in-scope"]}
	}
	"namespace-alias-qualified": {
		about: "after use package::types as t, t::User reaches the item"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types as t\n\n" + (_refHolder & {_ref: "t::User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"namespace-alias-original-refused": {
		about: "after use package::types as t, types is not in scope (fix: write t::User)"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types as t\n\n" + (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}

	// The forms that name an item bring in the item, and not the namespace.
	"item-bare": {
		about: "after use package::types::User, User reaches the item"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::User\n\n" + (_refHolder & {_ref: "User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"item-qualified-refused": {
		about: "after use package::types::User, types is not in scope (fix: write User)"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::User\n\n" + (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}
	"braces-bare": {
		about: "after use package::types::{User, Order}, User reaches the item"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::{User, Order}\n\n" + (_refHolder & {_ref: "User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"braces-qualified-refused": {
		about: "after use package::types::{User, Order}, types is not in scope (fix: write User)"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::{User, Order}\n\n" + (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}
	"glob-bare": {
		about: "after use package::types::*, User reaches the item"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::*\n\n" + (_refHolder & {_ref: "User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"glob-qualified-refused": {
		about: "after use package::types::*, types is not in scope (fix: write User)"
		packages: app: schemas: {
			types: _refTypes
			api:   "use package::types::*\n\n" + (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}
	"no-use-bare-refused": {
		about: "a bare User with no use is not in scope (fix: add use package::types::User, or write package::types::User)"
		packages: app: schemas: {
			types: _refTypes
			api:   (_refHolder & {_ref: "User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::not-in-scope"]}
	}
	"no-use-qualified-refused": {
		about: "types::User with no use is not rooted in a name in scope (fix: add use package::types, or write package::types::User)"
		packages: app: schemas: {
			types: _refTypes
			api:   (_refHolder & {_ref: "types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}

	// A full path works in a type position without a `use`.
	"full-package": {
		about: "package::types::User in a field needs no use"
		packages: app: schemas: {
			types: _refTypes
			api:   (_refHolder & {_ref: "package::types::User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-package-nested": {
		about: "package:: reaches a schema in a directory from one beside it, in a field"
		packages: app: schemas: {
			"shapes/types": _refTypes
			"shapes/api":   (_refHolder & {_ref: "package::shapes::types::User"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-parent": {
		about: "parent::common::Error in a field reaches a schema one level up from the importing schema's namespace"
		packages: app: schemas: {
			"shapes/common": "struct Error {\n    code: u32\n}"
			"shapes/api":    (_refHolder & {_ref: "parent::common::Error"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-self": {
		about: "self::nested::Type in a field reaches a schema under the importing schema's own namespace"
		packages: app: schemas: {
			"api":        (_refHolder & {_ref: "self::nested::Type"}).text
			"api/nested": "struct Type {\n    id: u32\n}"
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-std": {
		about: "std::http::Request in a field needs no use"
		packages: app: schemas: api: (_refHolder & {_ref: "std::http::Request"}).text
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-dependency": {
		about: "a dependency's greeting::hello::Greeting in a field needs no use"
		packages: {
			greeting: schemas: hello: _refGreeting
			app: {
				schemas: api: (_refHolder & {_ref: "greeting::hello::Greeting"}).text
				dependencies: greeting: {}
			}
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"full-own-schema-unrooted-refused": {
		about: "a full path to the package's own schema that doesn't start at package, parent or self is not rooted (fix: write package::shapes::types::User)"
		packages: app: schemas: {
			"shapes/types": _refTypes
			"api":          (_refHolder & {_ref: "shapes::types::User"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}

	// A path goes down from a name in scope.
	"descend-namespace": {
		about: "after use package::billing, billing::api::Invoice reaches the nested schema"
		packages: app: schemas: {
			"billing/api": _refBilling
			"api":         "use package::billing\n\n" + (_refHolder & {_ref: "billing::api::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"descend-alias": {
		about: "after use package::billing as b, b::api::Invoice reaches the nested schema"
		packages: app: schemas: {
			"billing/api": _refBilling
			"api":         "use package::billing as b\n\n" + (_refHolder & {_ref: "b::api::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"descend-dependency": {
		about: "after use greeting::hello, hello::Greeting reaches the dependency's item"
		packages: {
			greeting: schemas: hello: _refGreeting
			app: {
				schemas: api: "use greeting::hello\n\n" + (_refHolder & {_ref: "hello::Greeting"}).text
				dependencies: greeting: {}
			}
		}
		build: "app"
		expect: {builds: true, protocols: {}}
	}
	"descend-skips-a-segment-refused": {
		about: "after use package::billing, api is not in scope (fix: write billing::api::Invoice, or use package::billing::api)"
		packages: app: schemas: {
			"billing/api": _refBilling
			"api":         "use package::billing\n\n" + (_refHolder & {_ref: "api::Invoice"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["reference::qualifier-not-in-scope"]}
	}

	// A qualified reference is frozen as its resolved path: each spelling
	// reaches the `Invoice` in `billing/api`, and not the decoy in `archive`,
	// which an unmarked protocol using it can't give up.
	"resolved-item": {
		about: "use package::billing::api::Invoice, then Invoice, reaches billing::api::Invoice"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         "use package::billing::api::Invoice\n\n" + (_refOrders & {_ref: "Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: Orders: given_up: [], warnings: []}
	}
	"resolved-namespace": {
		about: "use package::billing::api, then api::Invoice, reaches billing::api::Invoice"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         "use package::billing::api\n\n" + (_refOrders & {_ref: "api::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: Orders: given_up: [], warnings: []}
	}
	"resolved-descent": {
		about: "use package::billing, then billing::api::Invoice, reaches billing::api::Invoice"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         "use package::billing\n\n" + (_refOrders & {_ref: "billing::api::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: Orders: given_up: [], warnings: []}
	}
	"resolved-alias": {
		about: "use package::billing::api as b, then b::Invoice, reaches billing::api::Invoice"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         "use package::billing::api as b\n\n" + (_refOrders & {_ref: "b::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: Orders: given_up: [], warnings: []}
	}
	"resolved-full-path": {
		about: "package::billing::api::Invoice with no use reaches billing::api::Invoice"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         (_refOrders & {_ref: "package::billing::api::Invoice"}).text
		}
		build: "app"
		expect: {builds: true, protocols: Orders: given_up: [], warnings: []}
	}
	"resolved-decoy": {
		about: "use package::archive, then archive::Invoice, reaches the unbounded Invoice, which an unmarked protocol can't use: the other cases reached billing's"
		packages: app: schemas: {
			"archive":     _refArchive
			"billing/api": _refBilling
			"api":         "use package::archive\n\n" + (_refOrders & {_ref: "archive::Invoice"}).text
		}
		build: "app"
		expect: {builds: false, errors: ["bounds::unbounded"]}
	}

	// A package written before the rule: a namespace `use` and references
	// qualified with the schema's namespace. Its protocols freeze as they did.
	"existing-package-unchanged": {
		about: "use package::models and models::Blob, as written before the rule, freezes the same protocols as the item use does in bounded/other-schema-marked"
		packages: app: {
			config: [_allow]
			schemas: {
				models: """
					struct Blob {
					    data: string
					}

					@unverified = "the uploader streams whatever it's given"
					protocol Upload {
					    function put(b: Blob);
					}
					"""
				api: """
					use package::models

					@unverified = "orders carry the upload"
					protocol Orders {
					    function send(b: models::Blob);
					}
					"""
			}
		}
		build: "app"
		expect: {
			builds: true
			protocols: {
				Upload: {
					given_up: ["bounded_size"]
					acknowledged: bounded_size: {scope: "protocol", reason: "the uploader streams whatever it's given"}
				}
				Orders: {
					given_up: ["bounded_size"]
					acknowledged: bounded_size: {scope: "protocol", reason: "orders carry the upload"}
				}
			}
			warnings: ["unverified::bounded-size"]
		}
	}
}
