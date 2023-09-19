SYSBOX_VERSION ?= v0.6.2

get-files:
	rm -rf ./tmp
	mkdir -p ./tmp/sysbox/amd64/bin
	mkdir -p ./tmp/sysbox/arm64/bin
	mkdir -p ./tmp/crio/amd64
	mkdir -p ./tmp/crio/arm64
	docker run --rm --platform linux/amd64 -v ./tmp:/host registry.nestybox.com/nestybox/sysbox-deploy-k8s:${SYSBOX_VERSION} /bin/bash -c "cp /opt/sysbox/bin/generic/* /host/sysbox/amd64/bin/ && cp -r /opt/sysbox/systemd/ /host/sysbox/systemd/ && cp -r /opt/crio-deploy/bin/* /host/crio/amd64/ && cp -r /opt/crio-deploy/config/ /host/crio/config/ && cp -r /opt/crio-deploy/scripts/ /host/crio/scripts/"
	docker run --rm --platform linux/arm64 -v ./tmp:/host registry.nestybox.com/nestybox/sysbox-deploy-k8s:${SYSBOX_VERSION} /bin/bash -c "cp /opt/sysbox/bin/generic/* /host/sysbox/arm64/bin/ && cp -r /opt/crio-deploy/bin/* /host/crio/arm64/"

packer-init:
	packer init .

packer-validate: get-files
	packer validate .

packer-build: packer-init packer-validate
	packer build .
