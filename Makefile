.PHONY: setup start foreground stop status health tool-test agent-smoke web-smoke benchmark test harness

setup:
	./scripts/setup.sh

start:
	./scripts/local-ai start

foreground:
	./scripts/local-ai foreground

stop:
	./scripts/local-ai stop

status:
	./scripts/local-ai status

health:
	./scripts/health-check.sh

tool-test:
	./scripts/tool-test.sh

agent-smoke:
	./scripts/opencode-smoke.sh

web-smoke:
	./scripts/opencode-web-smoke.sh

benchmark:
	./scripts/benchmark.sh

test:
	./scripts/test.sh

harness:
	./scripts/harness.sh
