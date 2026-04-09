#!/bin/bash
# Образ вже містить всі k8s prerequisites (зібрано через Packer).
# Cloud-init тільки гарантує swap вимкнений після кожного ребуту.
swapoff -a
