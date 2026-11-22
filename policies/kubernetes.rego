# Platform rules every vendor deployment must pass.
# Run in each PR by conftest (deploy-checks workflow) on the rendered manifests.
package main

import rego.v1

# --- Helper: every container of every Deployment ---------------------------------
containers contains c if {
	input.kind == "Deployment"
	some c in input.spec.template.spec.containers
}

# --- 1. Images only from our registry, pinned by digest -----------------------------
deny contains msg if {
	some c in containers
	not regex.match(`^[a-z0-9]+\.azurecr\.io/[a-z0-9/._-]+@sha256:[a-f0-9]{64}$`, c.image)
	msg := sprintf("%s: image '%s' must come from our ACR and be pinned by digest", [c.name, c.image])
}

# --- 2. No privileged containers ------------------------------------------------------
deny contains msg if {
	some c in containers
	c.securityContext.privileged == true
	msg := sprintf("%s: privileged containers are not allowed", [c.name])
}

# --- 3. CPU and memory limits are required ----------------------------------------------
deny contains msg if {
	some c in containers
	some r in ["cpu", "memory"]
	not c.resources.limits[r]
	msg := sprintf("%s: resources.limits.%s is required", [c.name, r])
}

# --- 4. Labels the 360 view relies on ---------------------------------------------------
required_labels := ["app.kubernetes.io/name", "app.kubernetes.io/version", "demo/vendor"]

deny contains msg if {
	input.kind == "Deployment"
	some l in required_labels
	not input.spec.template.metadata.labels[l]
	msg := sprintf("%s: pod label '%s' is required", [input.metadata.name, l])
}

# --- 5. No host networking ---------------------------------------------------------------
deny contains msg if {
	input.kind == "Deployment"
	input.spec.template.spec.hostNetwork == true
	msg := sprintf("%s: hostNetwork is not allowed", [input.metadata.name])
}
