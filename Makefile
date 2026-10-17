.PHONY: build app app-release install package launch quit status smoke smoke-destructive unit-test verify test docs

build:
	swift build

app:
	./scripts/build_app.sh

app-release:
	SPACESULTIMATE_CONFIGURATION=release ./scripts/build_app.sh

install:
	./scripts/install_app.sh

package:
	./scripts/package_release.sh

launch: app
	./scripts/launch_app.sh

quit:
	./scripts/quit_app.sh

status:
	./scripts/status_app.sh

smoke:
	./scripts/smoke_test_api.sh

smoke-destructive:
	SPACESULTIMATE_DESTRUCTIVE=1 ./scripts/smoke_test_api.sh

unit-test:
	swift test

verify: app
	./scripts/verify_app_bundle.sh

test: unit-test build smoke

docs:
	@printf '%s\n' docs/ARCHITECTURE.md docs/ROADMAP.md docs/TESTING.md docs/CHANGELOG.md
