SYSBOX_VERSION=v0.6.2

get-crio:
	rm -rf ./crio
	docker run --rm -it --platform linux/amd64 -v ./crio/amd64:/host/crio registry.nestybox.com/nestybox/sysbox-deploy-k8s:${SYSBOX_VERSION} /bin/bash -c "cp -r /opt/crio-deploy/bin/* /host/crio/"
	docker run --rm -it --platform linux/arm64 -v ./crio/arm64:/host/crio registry.nestybox.com/nestybox/sysbox-deploy-k8s:${SYSBOX_VERSION} /bin/bash -c "cp -r /opt/crio-deploy/bin/* /host/crio/"
# remove tar.gz files
	find ./crio/ -path '**/*.tar.gz' -delete
# remove empty directories
	find ./crio/ -empty -type d -delete
