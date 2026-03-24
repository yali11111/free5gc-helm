#!/bin/bash

set -e

echo "===== RA2 Xtesting + Minikube Setup ====="

# -----------------------------
# 1. Install dependencies
# -----------------------------
echo "[1/6] Installing dependencies..."

if ! command -v kubectl &> /dev/null; then
  echo "Installing kubectl..."
  curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
  chmod +x kubectl && sudo mv kubectl /usr/local/bin/
fi

if ! command -v minikube &> /dev/null; then
  echo "Installing Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  chmod +x minikube-linux-amd64 && sudo mv minikube-linux-amd64 /usr/local/bin/minikube
fi

if ! command -v python3 &> /dev/null; then
  echo "Installing Python..."
  sudo apt-get update && sudo apt-get install -y python3 python3-pip
fi

echo "Installing Xtesting..."
pip3 install --user xtesting kubernetes

export PATH=$PATH:$HOME/.local/bin

# -----------------------------
# 2. Start Minikube
# -----------------------------
echo "[2/6] Starting Minikube..."
minikube start --driver=docker

# -----------------------------
# 3. Create project structure
# -----------------------------
echo "[3/6] Creating project..."

mkdir -p ra2-xtesting/tests/k8s
cd ra2-xtesting

# xtesting.yaml
cat <<EOF > xtesting.yaml
project: ra2-minikube
case_dir: .
testcases_file: testcases.yaml
EOF

# testcases.yaml
cat <<EOF > testcases.yaml
tiers:
  - name: k8s
    testcases:
      - case_name: ra2.ch.001
        project_name: ra2-minikube
        run:
          module: tests.k8s.test_ra2_ch_001

      - case_name: ra2.k8s.006
        project_name: ra2-minikube
        run:
          module: tests.k8s.test_ra2_k8s_006

      - case_name: ra2.stg.001
        project_name: ra2-minikube
        run:
          module: tests.k8s.test_ra2_stg_001
EOF

# helper.py
cat <<EOF > tests/k8s/helper.py
import subprocess, json, time

def run_cmd(cmd):
    return subprocess.check_output(cmd, shell=True, text=True)

def apply_yaml(yaml):
    subprocess.run(f"kubectl apply -f - <<EOF\\n{yaml}\\nEOF", shell=True, check=True)

def wait_pod(name, timeout=60):
    for _ in range(timeout):
        try:
            out = run_cmd(f"kubectl get pod {name} -o json")
            phase = json.loads(out)["status"]["phase"]
            if phase in ["Running", "Succeeded"]:
                return True
        except:
            pass
        time.sleep(1)
    raise Exception("Pod not ready")
EOF

# -----------------------------
# 4. Test: HugePages
# -----------------------------
cat <<EOF > tests/k8s/test_ra2_ch_001.py
from xtesting.core.testcase import TestCase
from tests.k8s.helper import run_cmd

class HugePagesTest(TestCase):
    def run(self):
        output = run_cmd("kubectl describe node")
        if "hugepages-2Mi" in output:
            self.result = 100
            return 0
        self.result = 0
        return 1
EOF

# -----------------------------
# 5. Test: CPU pinning
# -----------------------------
cat <<EOF > tests/k8s/test_ra2_k8s_006.py
from xtesting.core.testcase import TestCase
from tests.k8s.helper import apply_yaml, wait_pod, run_cmd

class CpuTest(TestCase):
    def run(self):
        pod = """
apiVersion: v1
kind: Pod
metadata:
  name: guaranteed-test
spec:
  containers:
  - name: c
    image: busybox
    command: ["sleep", "20"]
    resources:
      requests:
        cpu: "1"
      limits:
        cpu: "1"
"""
        apply_yaml(pod)
        wait_pod("guaranteed-test")

        desc = run_cmd("kubectl describe pod guaranteed-test")
        if "Guaranteed" in desc:
            self.result = 100
            return 0
        self.result = 0
        return 1
EOF

# -----------------------------
# 6. Test: Storage
# -----------------------------
cat <<EOF > tests/k8s/test_ra2_stg_001.py
from xtesting.core.testcase import TestCase
from tests.k8s.helper import apply_yaml, wait_pod

class StorageTest(TestCase):
    def run(self):
        pod = """
apiVersion: v1
kind: Pod
metadata:
  name: storage-test
spec:
  containers:
  - name: c
    image: busybox
    command: ["sh", "-c", "echo ok > /data/file && sleep 20"]
    volumeMounts:
    - mountPath: /data
      name: tmp
  volumes:
  - name: tmp
    emptyDir: {}
"""
        apply_yaml(pod)
        wait_pod("storage-test")

        self.result = 100
        return 0
EOF

# init files
touch tests/__init__.py
touch tests/k8s/__init__.py

# -----------------------------
# 7. Run tests
# -----------------------------
echo "[6/6] Running Xtesting..."
xtesting
