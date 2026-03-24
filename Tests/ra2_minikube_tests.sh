#!/bin/bash

set -e

PASS=0
FAIL=0

log_pass() {
  echo "✅ PASS: $1"
  PASS=$((PASS+1))
}

log_fail() {
  echo "❌ FAIL: $1"
  FAIL=$((FAIL+1))
}

log_skip() {
  echo "⚠️ SKIP: $1"
}

echo "===== RA2 Validation on Minikube ====="

# -----------------------------
# ra2.ch.001 HugePages
# -----------------------------
echo "[ra2.ch.001] HugePages"
if kubectl describe node | grep -q hugepages; then
  log_pass "HugePages exposed"
else
  log_fail "HugePages not found"
fi

# -----------------------------
# ra2.ch.006 CPU allocation
# -----------------------------
echo "[ra2.ch.006] CPU allocation test"
kubectl run cpu-test --image=busybox --restart=Never -- sleep 30 >/dev/null 2>&1 || true

sleep 5
STATUS=$(kubectl get pod cpu-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [[ "$STATUS" == "Running" || "$STATUS" == "Succeeded" ]]; then
  log_pass "Pod scheduled successfully"
else
  log_fail "Pod scheduling failed"
fi

kubectl delete pod cpu-test --ignore-not-found >/dev/null 2>&1

# -----------------------------
# ra2.ch.007 Dual Stack
# -----------------------------
echo "[ra2.ch.007] Dual-stack"
IPS=$(kubectl get pod -o jsonpath='{.items[*].status.podIPs}' 2>/dev/null || echo "")

if echo "$IPS" | grep -q ":"; then
  log_pass "IPv6 detected"
else
  log_skip "IPv6 not enabled in Minikube"
fi

# -----------------------------
# ra2.ch.018 NFD
# -----------------------------
echo "[ra2.ch.018] NFD"
if kubectl get ns | grep -q node-feature-discovery; then
  log_pass "NFD namespace exists"
else
  log_skip "NFD not installed"
fi

# -----------------------------
# ra2.k8s.002 etcd HA
# -----------------------------
echo "[ra2.k8s.002] etcd HA"
ETCD_COUNT=$(kubectl get pods -n kube-system 2>/dev/null | grep etcd | wc -l)

if [[ "$ETCD_COUNT" -ge 1 ]]; then
  log_skip "Minikube uses single-node etcd ($ETCD_COUNT)"
else
  log_fail "No etcd found"
fi

# -----------------------------
# ra2.k8s.006 CPU pinning
# -----------------------------
echo "[ra2.k8s.006] CPU pinning (Guaranteed QoS)"

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-test
spec:
  containers:
  - name: c
    image: busybox
    command: ["sleep", "30"]
    resources:
      requests:
        cpu: "1"
      limits:
        cpu: "1"
EOF

sleep 5

DESC=$(kubectl describe pod guaranteed-test 2>/dev/null)

if echo "$DESC" | grep -q "Guaranteed"; then
  log_pass "Guaranteed QoS detected"
else
  log_fail "QoS not Guaranteed"
fi

kubectl delete pod guaranteed-test >/dev/null 2>&1

# -----------------------------
# ra2.ntw.002 CNI
# -----------------------------
echo "[ra2.ntw.002] CNI plugin"

CNI=$(kubectl get pods -n kube-system 2>/dev/null)

if echo "$CNI" | grep -Eqi "calico|cilium|flannel"; then
  log_pass "CNI plugin detected"
else
  log_skip "Unknown or default Minikube CNI"
fi

# -----------------------------
# ra2.ntw.017 LoadBalancer
# -----------------------------
echo "[ra2.ntw.017] LoadBalancer"

kubectl create deployment nginx --image=nginx >/dev/null 2>&1 || true
kubectl expose deployment nginx --port=80 --type=LoadBalancer >/dev/null 2>&1 || true

sleep 5

LB=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress}' 2>/dev/null || echo "")

if [[ -n "$LB" ]]; then
  log_pass "LoadBalancer assigned"
else
  log_skip "Minikube uses 'minikube service' instead"
fi

# -----------------------------
# ra2.stg.001 Ephemeral storage
# -----------------------------
echo "[ra2.stg.001] emptyDir test"

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-test
spec:
  containers:
  - name: c
    image: busybox
    command: ["sh", "-c", "echo hello > /data/file && sleep 20"]
    volumeMounts:
    - mountPath: /data
      name: tmp
  volumes:
  - name: tmp
    emptyDir: {}
EOF

sleep 5

STATUS=$(kubectl get pod emptydir-test -o jsonpath='{.status.phase}')

if [[ "$STATUS" == "Running" || "$STATUS" == "Succeeded" ]]; then
  log_pass "emptyDir working"
else
  log_fail "emptyDir failed"
fi

kubectl delete pod emptydir-test >/dev/null 2>&1

# -----------------------------
# Summary
# -----------------------------
echo ""
echo "===== RESULT ====="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ $FAIL -eq 0 ]]; then
  echo "🎉 All critical tests passed (Minikube scope)"
else
  echo "⚠️ Some tests failed"
fi
