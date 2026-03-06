# helm-observability-stack

Stack completa de observabilidade instalada com **um único comando Helm**.

Inclui: **Grafana 12 · Loki 3.6 · Promtail 3.5 · Tempo · Prometheus**

---

## Componentes

| Componente | Chart | Versão | Função |
|---|---|---|---|
| Grafana | `grafana/grafana` | 10.5.15 (app 12.x) | UI — métricas, logs, traces |
| Loki | `grafana/loki` | 6.53.0 (app 3.6.5) | Armazenamento de logs |
| Promtail | `grafana/promtail` | 6.17.1 (app 3.5.1) | Coleta logs dos pods (DaemonSet) |
| Tempo | `grafana/tempo` | 1.24.4 | Traces distribuídos (OTLP/Jaeger) |
| Prometheus | `prometheus-community/prometheus` | 28.13.0 | Métricas do cluster |
| kube-state-metrics | subchart do prometheus | — | Métricas de objetos K8s |
| node-exporter | subchart do prometheus | — | Métricas de nodes |

---

## Pré-requisitos

```bash
helm version    # >= 3.12
kubectl version # >= 1.27
```

Repositórios Helm (adicionar uma vez):

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

## Quickstart

```bash
git clone https://github.com/rturatti/helm-observability-stack.git
cd helm-observability-stack

# 1. Baixar dependências
helm dependency update

# 2. Instalar (produção)
helm install obs . \
  --namespace observability \
  --create-namespace \
  -f values.yaml \
  --timeout 15m \
  --wait

# 3. Recuperar a senha do Grafana (gerada automaticamente)
kubectl get secret -n observability grafana-admin-secret \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

---

## Deploy Local com Kind

### 1 — Criar o cluster Kind

```bash
cat <<EOF | kind create cluster --name observability-local --config -
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000
        hostPort: 3000
      - containerPort: 30001
        hostPort: 9090
EOF

# Fix inotify para WSL2 (necessário para o Promtail)
docker exec observability-local-control-plane sysctl -w fs.inotify.max_user_watches=524288
docker exec observability-local-control-plane sysctl -w fs.inotify.max_user_instances=512
```

### 2 — Instalar

```bash
helm dependency update

helm install obs . \
  --namespace observability \
  --create-namespace \
  --kube-context kind-observability-local \
  -f values.yaml \
  -f values-kind.yaml \
  --set global.adminPassword=admin123 \
  --timeout 15m \
  --wait
```

### 3 — Acessar

| Serviço | URL | Credenciais |
|---|---|---|
| Grafana | http://localhost:3000 | admin / admin123 |
| Prometheus | http://localhost:9090 | — |

---

## Estrutura

```
helm-observability-stack/
├── Chart.yaml              # Declara as 5 dependências
├── Chart.lock              # Versões travadas (reproduzível)
├── values.yaml             # Configuração base (produção)
├── values-kind.yaml        # Overrides para Kind local (NodePort, PVCs menores)
├── README.md
└── templates/
    ├── _helpers.tpl                # URLs de serviço, labels, nomes
    ├── NOTES.txt                   # Instruções pós-install
    ├── namespace.yaml              # Namespace (opcional, via global.createNamespace)
    ├── grafana-admin-secret.yaml   # Senha com geração e persistência automática
    └── grafana-datasources.yaml    # ConfigMap de datasources (Loki, Prometheus, Tempo)
```

> **Nota:** a pasta `charts/` com os `.tgz` está no `.gitignore`.  
> Execute `helm dependency update` antes do primeiro `helm install`.

---

## Configurações principais

### Senha do Grafana

O chart gerencia a senha automaticamente:

```
helm install (primeira vez)
    ├─ --set global.adminPassword=MinhaS3nha  → usa o valor fornecido
    └─ (vazio)                                → gera 20 chars aleatórios

helm upgrade (próximas vezes)
    └─ Secret já existe → mantém a senha existente (idempotente)
```

Para ver a senha gerada:
```bash
kubectl get secret -n observability grafana-admin-secret \
  -o jsonpath="{.data.admin-password}" | base64 -d && echo
```

### Datasources pré-configurados

Provisionados automaticamente via ConfigMap + sidecar do Grafana:

| Datasource | URL interna | UID |
|---|---|---|
| Loki | `http://obs-loki:3100` | `loki` |
| Prometheus | `http://obs-prometheus-server:80` | `prometheus` |
| Tempo | `http://obs-tempo:3200` | `tempo` |

O Tempo é configurado com **Traces → Logs** (navegar de um trace direto para os logs do Loki).

### Desabilitar componentes

```bash
helm install obs . -n observability --create-namespace \
  --set tempo.enabled=false \
  --set prometheus.alertmanager.enabled=false
```

### Ingress para o Grafana

```yaml
# values.yaml ou --set
grafana:
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.seudominio.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.seudominio.com
```

### Storage class customizada (EKS/GKE/AKS)

```yaml
grafana:
  persistence:
    storageClassName: gp3

loki:
  singleBinary:
    persistence:
      storageClassName: gp3

prometheus:
  server:
    persistentVolume:
      storageClassName: gp3
```

### Tamanho dos PVCs

```yaml
# values.yaml
grafana:
  persistence:
    size: 20Gi

loki:
  singleBinary:
    persistence:
      size: 100Gi

prometheus:
  server:
    persistentVolume:
      size: 100Gi
```

### Release name diferente de `obs`

O chart é totalmente dinâmico — os helpers em `_helpers.tpl` constroem as URLs com base no `{{ .Release.Name }}`:

| Helper | URL (release=obs) | URL (release=monitor) |
|---|---|---|
| `observability.lokiUrl` | `http://obs-loki:3100` | `http://monitor-loki:3100` |
| `observability.prometheusUrl` | `http://obs-prometheus-server:80` | `http://monitor-prometheus-server:80` |
| `observability.tempoUrl` | `http://obs-tempo:3200` | `http://monitor-tempo:3200` |

---

## Operações

```bash
# Status
helm status obs -n observability
kubectl get pods -n observability

# Upgrade
helm upgrade obs . -n observability -f values.yaml

# Rollback
helm rollback obs -n observability

# Remover (o Secret da senha é preservado por resource-policy: keep)
helm uninstall obs -n observability
kubectl delete secret grafana-admin-secret -n observability  # opcional
kubectl delete namespace observability                        # opcional
```

---

## Troubleshooting

### Pods em Pending (PVC não bound)

```bash
kubectl get pvc -n observability
kubectl describe pvc <nome> -n observability
# Verificar storage classes disponíveis:
kubectl get storageclass
```

### Grafana em CrashLoopBackOff

```bash
kubectl logs -n observability deployment/obs-grafana -c grafana
# Causas comuns:
# - Secret grafana-admin-secret não existe
# - Datasource duplicado com isDefault: true
```

### Promtail — "too many open files" (WSL2 / Kind)

```bash
docker exec observability-local-control-plane sysctl -w fs.inotify.max_user_watches=524288
docker exec observability-local-control-plane sysctl -w fs.inotify.max_user_instances=512
kubectl rollout restart daemonset/obs-promtail -n observability
```

### Logs Drilldown mostra 404

Requer Loki 3.x com `volume_enabled: true` (já configurado neste chart).  
Verifique se o endpoint responde:
```bash
kubectl port-forward -n observability svc/obs-loki 3100:3100 &
curl http://localhost:3100/loki/api/v1/drilldown-limits
```

### Datasource não aparece no Grafana

```bash
# ConfigMaps com a label do sidecar
kubectl get configmap -n observability -l grafana_datasource=1

# Logs do sidecar
kubectl logs -n observability deployment/obs-grafana -c grafana-sc-datasources
```

### Listar todos os recursos criados

```bash
helm get manifest obs -n observability | grep "^kind:" | sort | uniq -c
```

---

## Logs Drilldown (Grafana 12+)

Este chart usa **Loki 3.6.5** que suporta as APIs exigidas pelo plugin `grafana-lokiexplore-app`:
- `/loki/api/v1/index/volume` ✓
- `/loki/api/v1/drilldown-limits` ✓

O plugin é instalado automaticamente pelo Grafana no primeiro boot.  
Acesse via **Menu → Drilldown → Logs**.

---

## Licença

MIT
