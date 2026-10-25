.PHONY: build app app-release install package launch quit status smoke unit-test script-test verify test

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

launch:
	./scripts/launch_app.sh

quit:
	./scripts/quit_app.sh

status:
	./scripts/status_app.sh

smoke:
	./scripts/smoke_test_api.sh

unit-test:
	swift test

script-test:
	python3 -m unittest discover -s Tests/Scripts -p 'test_*.py'

verify: app
	./scripts/verify_app_bundle.sh

test: unit-test script-test verify
