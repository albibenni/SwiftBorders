.PHONY: release

release:
	@type=$(type); \
	if [ -z "$$type" ]; then type="patch"; fi; \
	echo "Starting $$type release..."; \
	latest_tag=$$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"); \
	latest_version=$${latest_tag#v}; \
	major=$$(echo $$latest_version | cut -d. -f1); \
	minor=$$(echo $$latest_version | cut -d. -f2); \
	patch=$$(echo $$latest_version | cut -d. -f3); \
	if [ "$$type" = "major" ]; then \
		major=$$((major + 1)); minor=0; patch=0; \
	elif [ "$$type" = "minor" ]; then \
		minor=$$((minor + 1)); patch=0; \
	else \
		patch=$$((patch + 1)); \
	fi; \
	new_version="$$major.$$minor.$$patch"; \
	echo "Bumping version: v$$latest_version -> v$$new_version"; \
	git tag "v$$new_version"; \
	git push origin main; \
	git push origin "v$$new_version"; \
	echo "\n🎉 Successfully released v$$new_version! GitHub Actions will now build the release and update Homebrew."
