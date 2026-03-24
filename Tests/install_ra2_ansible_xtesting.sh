#!/bin/bash

set -e

echo "===== RA2 Xtesting via Ansible (Collivier-style) ====="

# -----------------------------
# 1. Install dependencies
# -----------------------------
echo "[1/5] Installing dependencies..."

if ! command -v ansible &> /dev/null; then
  sudo apt-get update
  sudo apt-get install -y ansible python3-pip git
fi

pip3 install --user kubernetes xtesting
export PATH=$PATH:$HOME/.local/bin

# -----------------------------
# 2. Create workspace
# -----------------------------
echo "[2/5] Preparing workspace..."

WORKDIR=$HOME/ra2-ansible
mkdir -p $WORKDIR
cd $WORKDIR

# -----------------------------
# 3. Create role (collivier style)
# -----------------------------
echo "[3/5] Creating Ansible role..."

ansible-galaxy init collivier.ra2_xtesting

cd collivier.ra2_xtesting

# defaults
cat <<EOF > defaults/main.yml
minikube_driver: docker
xtesting_project_dir: /opt/ra2-xtesting
run_tests: true
EOF

# main task
mkdir -p tasks
cat <<EOF > tasks/main.yml
- import_tasks: install.yml
- import_tasks: minikube.yml
- import_tasks: xtesting.yml
- import_tasks: tests.yml
  when: run_tests
EOF

# -----------------------------
# install.yml
# -----------------------------
cat <<EOF > tasks/install.yml
- name: Install system packages
  apt:
    name:
      - curl
      - docker.io
      - python3-pip
    state: present
    update_cache: yes

- name: Install kubectl
  shell: |
    curl -LO https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /usr/local/bin/
  args:
    creates: /usr/local/bin/kubectl

- name: Install Minikube
  shell: |
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    install minikube-linux-amd64 /usr/local/bin/minikube
  args:
    creates: /usr/local/bin/minikube

- name: Install Python deps
  pip:
    name:
      - xtesting
      - kubernetes
EOF

# -----------------------------
# minikube.yml
# -----------------------------
cat <<EOF > tasks/minikube.yml
- name: Start Minikube
  command: minikube start --driver={{ minikube_driver }}
  register: mk
  changed_when: "'Done!' in mk.stdout"
EOF

# -----------------------------
# xtesting.yml
# -----------------------------
cat <<EOF > tasks/xtesting.yml
- name: Create project dir
  file:
    path: "{{ xtesting_project_dir }}"
    state: directory

- name: Create test dirs
  file:
    path: "{{ xtesting_project_dir }}/tests/k8s"
    state: directory
    recurse: yes

- name: xtesting config
  copy:
    dest: "{{ xtesting_project_dir }}/xtesting.yaml"
    content: |
      project: ra2-minikube
      case_dir: .
      testcases_file: testcases.yaml

- name: testcases
  copy:
    dest: "{{ xtesting_project_dir }}/testcases.yaml"
    content: |
      tiers:
        - name: k8s
          testcases:
            - case_name: ra2.k8s.006
              project_name: ra2-minikube
              run:
                module: tests.k8s.test_cpu

- name: test file
  copy:
    dest: "{{ xtesting_project_dir }}/tests/k8s/test_cpu.py"
    content: |
      from xtesting.core.testcase import TestCase
      import subprocess

      def run_cmd(cmd):
          return subprocess.check_output(cmd, shell=True, text=True)

      class CpuTest(TestCase):
          def run(self):
              subprocess.run("kubectl run test --image=busybox -- sleep 20", shell=True)

              desc = run_cmd("kubectl describe pod test")
              if "Guaranteed" in desc:
                  self.result = 100
                  return 0
              self.result = 0
              return 1
EOF

# -----------------------------
# tests.yml
# -----------------------------
cat <<EOF > tasks/tests.yml
- name: Run Xtesting
  command: xtesting
  args:
    chdir: "{{ xtesting_project_dir }}"
  register: out

- debug:
    var: out.stdout
EOF

# -----------------------------
# 4. Create playbook
# -----------------------------
cd $WORKDIR

cat <<EOF > playbook.yml
- hosts: localhost
  become: yes
  roles:
    - collivier.ra2_xtesting
EOF

# -----------------------------
# 5. Run playbook
# -----------------------------
echo "[5/5] Running Ansible..."

ansible-playbook -i localhost, -c local playbook.yml

echo "===== DONE ====="
