# coredns-docker-discovery

**Docker Discovery Plugin for CoreDNS**

[![Docker Pulls](https://img.shields.io/docker/pulls/vxcontrol/coredns-docker-discovery)](https://hub.docker.com/r/vxcontrol/coredns-docker-discovery)

## Table of Contents

- [Description](#description)
- [Getting Started - Docker Usage](#getting-started---docker-usage)
- [Configuration - Corefile Syntax](#configuration---corefile-syntax)
- [How DNS Names Are Resolved](#how-dns-names-are-resolved)
- [TTL and Caching](#ttl-and-caching)
- [Example Usage](#example-usage)
- [Building Docker Image](#building-docker-image)
- [Building from Source](#building-from-source-optional)
- [Troubleshooting & FAQ](#troubleshooting--faq)
- [Acknowledgements](#acknowledgements)

## Description

`coredns-docker-discovery` is a CoreDNS plugin that automatically manages DNS records for your Docker containers. It dynamically adds and removes DNS entries as containers are started and stopped, making service discovery within Docker environments seamless.

**Key Features:**

* **Automatic DNS Registration** - Containers are automatically registered in DNS when started
* **Real-time Updates** - DNS records update instantly when containers start, stop, or change networks
* **Multiple Resolution Methods** - Resolve by container name, hostname, compose service, network aliases, or custom labels
* **Multi-network Support** - Handle containers connected to multiple Docker networks
* **High Performance** - In-memory lookup with microsecond latency, no Docker API calls during DNS queries
* **IPv4 and IPv6 Support** - Full support for both A and AAAA DNS records
* **Flexible Configuration** - Combine multiple resolution methods for the same container

This plugin allows you to resolve Docker containers by:

* **Container Name:**  Using the container's `--name` as a subdomain.
* **Hostname:** Using the container's `--hostname` as a subdomain.
* **Docker Compose Project & Service Names:** For containers managed by Docker Compose.
* **Network Aliases:** Leveraging Docker network aliases for resolution within a specific network.
* **Labels:**  Resolving containers based on custom labels.

## Getting Started - Docker Usage

The easiest way to use `coredns-docker-discovery` is by running the pre-built Docker image. This eliminates the need to build CoreDNS and the plugin manually.

**1. Pull the Docker Image:**

```bash
docker pull vxcontrol/coredns-docker-discovery:latest
```

**2. Create a Corefile:**

You'll need a Corefile to configure CoreDNS and the `dockerdiscovery` plugin.  Here's a basic example that listens on port 15353 and uses `dockerdiscovery` for the `loc` domain:

```
# Corefile
.:15353 {
    docker {
        domain docker.loc
    }
    log
}
```

**3. Run the CoreDNS Docker Container:**

Mount your Corefile and the Docker socket into the container.  Make sure to expose the desired port (e.g., 15353/UDP) for DNS queries.

```bash
docker run -d \
  --name coredns-docker-discovery \
  -v ${PWD}/Corefile:/etc/Corefile \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 15353:15353/udp \
  vxcontrol/coredns-docker-discovery -conf /etc/Corefile
```

**Explanation:**

* `-d`: Runs the container in detached mode (background).
* `--name coredns-docker-discovery`: Assigns a name to the container.
* `-v ${PWD}/Corefile:/etc/Corefile`: Mounts your local `Corefile` to `/etc/Corefile` inside the container.
* `-v /var/run/docker.sock:/var/run/docker.sock`:  Mounts the Docker socket, allowing CoreDNS to communicate with the Docker daemon. **This is crucial for Docker discovery to work.**
* `-p 15353:15353/udp`:  Maps port 15353 on the host to port 15353 (UDP) in the container.  This is the port CoreDNS will listen on for DNS queries.
* `vxcontrol/coredns-docker-discovery -conf /etc/Corefile`: Specifies the Docker image to use and tells CoreDNS to use the Corefile at `/etc/Corefile`.

## Configuration - Corefile Syntax

Within your Corefile, use the `docker` plugin block to configure Docker discovery:

```
docker [DOCKER_ENDPOINT] {
    domain DOMAIN_NAME
    hostname_domain HOSTNAME_DOMAIN_NAME
    network_aliases DOCKER_NETWORK
    filter_network DOCKER_NETWORK
    label LABEL
    compose_domain COMPOSE_DOMAIN_NAME
    ttl TTL_SECONDS
}
```

**Parameters:**

* **`DOCKER_ENDPOINT` (Optional):**
    - Path to the Docker socket. Defaults to `unix:///var/run/docker.sock`.
    - Can also be a TCP socket (e.g., `tcp://127.0.0.1:999`).
    - **When running CoreDNS inside Docker, you typically mount `/var/run/docker.sock` and can omit this parameter, using the default.**

* **`domain DOMAIN_NAME` (Optional):**
    - The base domain for container names.
    - Creates DNS records using the container's `--name` as subdomain.
    - Example: `domain docker.loc` will resolve containers named `my-nginx` as `my-nginx.docker.loc`.
    - **Note:** This works in addition to other resolvers, not instead of them.

* **`hostname_domain HOSTNAME_DOMAIN_NAME` (Optional):**
    - The base domain for container hostnames.
    - Creates DNS records using the container's `--hostname` as subdomain.
    - Example: `hostname_domain docker-host.loc` will resolve containers with hostname `alpine` as `alpine.docker-host.loc`.
    - **Note:** This is independent of `domain` - both can be used together.

* **`compose_domain COMPOSE_DOMAIN_NAME` (Optional):**
    - The base domain for Docker Compose projects and services.
    - Creates DNS records using Docker Compose labels (automatically set by docker-compose).
    - Format: `<service>.<project>.<compose_domain>`
    - For a Compose project named "internal" and service "nginx", with `compose_domain compose.loc`, the FQDN will be `nginx.internal.compose.loc`.
    - **Note:** Only works for containers started with docker-compose.

* **`network_aliases DOCKER_NETWORK` (Optional):**
    - The name of a Docker network.
    - Extracts and uses Docker network aliases from the specified network as DNS names.
    - Aliases are used as-is (no domain suffix added).
    - Can create multiple DNS records if container has multiple aliases in that network.
    - Example: `--network my_net --network-alias api.loc --network-alias backend.loc` will create both `api.loc` and `backend.loc` DNS records.
    - **Note:** This option extracts DNS names from network aliases, but does NOT filter which containers are registered. Use `filter_network` for filtering.

* **`filter_network DOCKER_NETWORK` (Optional):**
    - The name of a Docker network to filter containers by.
    - **Filters which containers are registered:** Only containers connected to this network will be added to DNS.
    - **Determines IP address:** For containers with multiple networks, only the IP address from this network will be used.
    - Containers not in this network will be completely ignored (no DNS records created).
    - **Important:** This is separate from `network_aliases`. You can use `filter_network` without `network_aliases` and vice versa.
    - **Use case:** Essential for environments with multiple Docker networks where you want to isolate DNS records to a specific network.

* **`label LABEL` (Optional):**
    - Container label used for custom DNS name resolution.
    - Defaults to `coredns.dockerdiscovery.host`.
    - The label value is used as the **complete DNS name** (no domain suffix added).
    - **Always active** even if not explicitly configured in Corefile.
    - Example: `docker run --label coredns.dockerdiscovery.host=my-api.prod.loc nginx` will resolve as `my-api.prod.loc`.
    - You can change the label name: `label my.custom.label` will look for containers with `my.custom.label` instead.

* **`ttl TTL_SECONDS` (Optional):**
    - Time to live for DNS records in seconds.
    - Defaults to 3600 seconds (1 hour).
    - **What it does:** Controls how long DNS clients can cache the DNS response.
    - Lower TTL = faster updates when containers change, but more DNS queries.
    - Higher TTL = fewer DNS queries, but slower to detect changes.
    - See the [TTL and Caching](#ttl-and-caching) section for detailed explanation and recommendations.

## How DNS Names Are Resolved

**Important:** A single container can have **multiple DNS names** simultaneously! Each configuration option (domain, hostname_domain, etc.) creates additional DNS records for the same container.

### DNS Name Resolution Priority

The plugin uses multiple "resolvers" that work in parallel. All resolvers process each container, and their results are combined:

1. **Label Resolver** (Always Active)
   - Looks for the label `coredns.dockerdiscovery.host` (or custom label set via `label` option)
   - The label value is used as the **complete DNS name** (no domain suffix added)
   - Example: `--label coredns.dockerdiscovery.host=api.production.loc` → resolves as `api.production.loc`

2. **Container Name Resolver** (Active when `domain` is configured)
   - Uses the container's `--name` as subdomain
   - Format: `<container-name>.<domain>`
   - Example: Container named `payment-service` with `domain docker.loc` → `payment-service.docker.loc`

3. **Hostname Resolver** (Active when `hostname_domain` is configured)
   - Uses the container's `--hostname` as subdomain
   - Format: `<hostname>.<hostname_domain>`
   - Example: Container with `--hostname api-server` and `hostname_domain host.loc` → `api-server.host.loc`

4. **Compose Resolver** (Active when `compose_domain` is configured)
   - Uses Docker Compose labels to create names
   - Format: `<service>.<project>.<compose_domain>`
   - Automatically set by docker-compose based on service and project names
   - Example: Service `web` in project `myapp` with `compose_domain compose.loc` → `web.myapp.compose.loc`

5. **Network Aliases Resolver** (Active when `network_aliases` is configured)
   - Extracts network aliases from the specified Docker network
   - Uses aliases as-is (no domain suffix added)
   - Can return multiple names if container has multiple aliases
   - Example: `--network-alias api.internal.loc --network-alias backend.loc` → both names will resolve

### IP Address Selection

When a container is connected to multiple networks, the plugin determines which IP to use:

1. **Label `coredns.dockerdiscovery.network`** (Highest Priority)
   - If present, uses IP from the network specified in this label
   
2. **`filter_network` option** (Second Priority)
   - If configured, uses IP from the specified network
   - Containers not in this network are completely ignored
   
3. **Automatic Selection** (Fallback)
   - For single-network containers: uses that network's IP
   - For multi-network containers: uses `NetworkMode` or default network IP

### Complete Example

Let's see how multiple DNS names work for a single container:

```yaml
# docker-compose.yml
version: "3.7"
services:
  payment-api:
    image: nginx
    container_name: payment-prod
    hostname: payment-processor
    networks:
      app-network:
        aliases:
          - pay.internal.loc
          - payment.internal.loc
    labels:
      coredns.dockerdiscovery.host: secure-payment.prod.loc
```

```
# Corefile
.:15353 {
    docker {
        domain docker.loc
        hostname_domain host.loc
        compose_domain compose.loc
        network_aliases app-network
    }
    log
}
```

**Result: This single container gets 6 DNS names!**

| DNS Name | Source | Resolver |
|----------|--------|----------|
| `secure-payment.prod.loc` | Label `coredns.dockerdiscovery.host` | Label Resolver |
| `payment-prod.docker.loc` | Container name | Container Name Resolver |
| `payment-processor.host.loc` | Hostname | Hostname Resolver |
| `payment-api.myproject.compose.loc` | Compose labels | Compose Resolver |
| `pay.internal.loc` | Network alias #1 | Network Aliases Resolver |
| `payment.internal.loc` | Network alias #2 | Network Aliases Resolver |

All these names will resolve to the same IP address!

```bash
dig @localhost -p 15353 secure-payment.prod.loc        # Returns 172.20.0.5
dig @localhost -p 15353 payment-prod.docker.loc        # Returns 172.20.0.5
dig @localhost -p 15353 pay.internal.loc               # Returns 172.20.0.5
# All return the same IP!
```

### Important Notes

1. **Multiple DNS Names Are Additive**
   - Each configured option (domain, hostname_domain, etc.) adds MORE DNS names, not replaces them
   - To get only specific types of names, configure only those options

2. **Label Resolver Is Always Active**
   - Even with minimal configuration, containers with `coredns.dockerdiscovery.host` label will be resolved
   - This cannot be disabled, only the label name can be changed

3. **Network Aliases vs Filter Network**
   - `network_aliases my_net` → extracts DNS names from aliases in `my_net`
   - `filter_network my_net` → only registers containers that are in `my_net`
   - These are independent options and can be used separately or together

4. **Containers with Multiple Networks**
   - Without `filter_network`: may cause errors if the plugin cannot determine which IP to use
   - With `filter_network`: always uses IP from the specified network
   - With label `coredns.dockerdiscovery.network`: label takes priority over `filter_network`

5. **Minimal Configuration**
   ```
   docker {
       # No options - only label resolver is active
   }
   ```
   This will only resolve containers with the `coredns.dockerdiscovery.host` label.

## TTL and Caching

### What is TTL?

**TTL (Time To Live)** controls how long DNS clients cache responses before re-querying the server.

```bash
$ dig @localhost -p 15353 my-app.docker.loc

;; ANSWER SECTION:
my-app.docker.loc.      300     IN      A       172.20.0.5
                        ↑
                   TTL = 300 seconds
```

Lower TTL = faster updates when containers change, but more DNS queries.  
Higher TTL = fewer queries, but slower to detect IP changes.

### TTL vs CoreDNS Cache

**Important:** Plugin's `ttl` is different from CoreDNS's `cache`:

```
.:15353 {
    docker {
        ttl 300      # ← Client cache time
    }
    cache 300        # ← CoreDNS internal cache
}
```

**Rule: Always set `ttl ≤ cache`** to avoid stale data on clients.

**Example problem if `ttl > cache`:**
```
docker { ttl 600 }  # 10 minutes
cache 300           # 5 minutes

Result: Clients may use stale IP for up to 5 minutes after CoreDNS learns about changes!
```

### Performance & When to Use Cache

Plugin is fast (all data in RAM, no Docker API calls during queries):

| Containers | Without cache | With cache | Recommendation |
|------------|--------------|------------|----------------|
| < 50 | ~5 μs | ~2 μs | Cache optional |
| 50-200 | ~30 μs | ~2 μs | Cache recommended |
| > 200 | ~200 μs | ~2 μs | **Cache required** |

### TTL Recommendations by Environment

| Environment | TTL | Cache | Why |
|-------------|-----|-------|-----|
| **Development** | 30 | 30 | Frequent container changes |
| **Staging** | 300 | 300 | Balanced |
| **Production (stable)** | 1800 | 1800 | Containers rarely change |
| **Production (auto-scale)** | 300 | 300 | Frequent scaling |
| **CI/CD** | 10-30 | 10-30 | Very frequent changes |

**Tip:** Start with `ttl 300` and `cache 300` (5 minutes) - works well for most cases.

## Example Usage

**1. Corefile (e.g., `Corefile` ):**

```
.:15353 {
    docker {
        domain docker.loc
    }
    log
}
```

**2. Start CoreDNS (using the Docker image as described in "Getting Started - Docker Usage").**

**3. Start a Docker Container (with a name and hostname):**

```bash
docker run -d --name my-alpine --hostname alpine alpine sleep 1000
```

**4. Resolve the Container:**

Use `dig` or `nslookup` to query CoreDNS (running at `localhost:15353` in this example):

```bash
dig @localhost -p 15353 my-alpine.docker.loc
dig @localhost -p 15353 alpine.docker-host.loc
```

You should see an `ANSWER SECTION` in the `dig` output containing the container's IP address.

**5. Docker Compose Example:**

Assume you have a Docker Compose project named "my-project" and a service called "web". With the `compose_domain compose.loc` configured, you can resolve the service as `web.my-project.compose.loc` .

**6. Label-based Resolution:**

Start a container with a label:

```bash
docker run -d --label=coredns.dockerdiscovery.host=nginx.web.loc nginx
```

With the default label configuration, you can now resolve this container as `nginx.web.loc` .

**7. Multi-Network Environment with filter_network:**

For production environments with multiple Docker networks:

```
# Corefile
.:15353 {
    docker {
        domain app.loc
        network_aliases production-network
        filter_network production-network
    }
    log
}
```

```bash
# Create networks
docker network create production-network
docker network create monitoring-network

# Container in production network - will be registered
docker run -d --name api \
  --network production-network \
  --network-alias api.internal.loc \
  nginx
# Creates: api.app.loc, api.internal.loc

# Container in monitoring network only - will be ignored
docker run -d --name grafana \
  --network monitoring-network \
  grafana/grafana
# Creates: nothing (not in production-network)

# Container in both networks - will use production-network IP
docker run -d --name webapp \
  --network production-network \
  --network monitoring-network \
  nginx
# Creates: webapp.app.loc (using production-network IP only)
```

## Building Docker Image

### Local Build (for testing)

```bash
# Simple build for local testing
docker build -t coredns-docker-discovery:local .

# Test the image
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${PWD}/Corefile:/etc/Corefile \
  -p 15353:15353/udp \
  coredns-docker-discovery:local
```

### Multi-architecture Build (for Docker Hub)

**Prerequisites:**
- Docker Buildx
- Docker Hub account

**Setup buildx (one time):**

```bash
# Create and use buildx builder
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap
```

**Build and push multi-arch image:**

```bash
# Login to Docker Hub
docker login

# Build and push for amd64 and arm64
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t vxcontrol/coredns-docker-discovery:latest \
  -t vxcontrol/coredns-docker-discovery:v1.0.0 \
  --push \
  .
```

**Verify multi-arch image:**

```bash
docker manifest inspect vxcontrol/coredns-docker-discovery:latest
```

**Troubleshooting build errors:**

If you get "cannot find module providing package" error, ensure:
1. Plugin source code is copied to the builder (check `COPY . /go/src/github.com/vxcontrol/coredns-docker-discovery` line in Dockerfile)
2. `.dockerignore` doesn't exclude necessary files (should only exclude `.git*` and `Dockerfile`)

## Building from Source (Optional)

If you wish to build the plugin from source (for development or customization):

**Prerequisites:**

* Go (version specified in CoreDNS documentation)
* Git
* Docker (for building the Docker image)

**Steps:**

1. **Clone CoreDNS:**
   

```bash
   git clone https://github.com/coredns/coredns --depth=1 ./go/src/github.com/coredns/coredns
   ```

2. **Navigate to CoreDNS directory:**
   

```bash
   cd go/src/github.com/coredns/coredns
   ```

3. **Add plugin to `plugin.cfg`:**
   

```bash
   echo "docker:github.com/vxcontrol/coredns-docker-discovery" >> plugin.cfg
   ```

4. **Generate plugin code:**
   

```bash
   go generate
   ```

5. **Build CoreDNS:**
   

```bash
   CGO_ENABLED=1 make gen all
   ```

**Running Tests:**

```bash
go test -v github.com/vxcontrol/coredns-docker-discovery
```

## Troubleshooting & FAQ

### Q: Container IP changed but DNS still returns old IP

**Cause:** Client cache (TTL) hasn't expired yet.

**Solution:**
1. Wait for TTL to expire (check your `ttl` setting)
2. Clear DNS cache on your system:
   ```bash
   # Linux
   sudo systemd-resolve --flush-caches
   
   # macOS
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   
   # Windows
   ipconfig /flushdns
   ```
3. Reduce `ttl` value for development: `ttl 30`

### Q: Getting "unable to find network settings for the network X" errors

**Cause:** Container is connected to multiple networks but plugin can't determine which one to use.

**Solution:** Use `filter_network` option:
```
docker {
    domain app.loc
    filter_network my_network  # Specify which network to use
}
```

### Q: Container not appearing in DNS

**Possible causes and solutions:**

1. **No resolvers configured:**
   ```
   docker {
       # Need at least one: domain, hostname_domain, compose_domain, or network_aliases
       domain docker.loc
   }
   ```

2. **Using `filter_network` and container not in that network:**
   ```bash
   # Check container networks
   docker inspect my-container | grep Networks -A 20
   ```

3. **Container not running:**
   ```bash
   docker ps -a  # Check container status
   ```

4. **Check CoreDNS logs:**
   ```bash
   docker logs coredns-container
   # Look for "[docker] Add entry of container..." messages
   ```

### Q: DNS queries are slow

**Possible causes:**

1. **Too many containers without cache:**
   - 200+ containers: ~100-500μs per query
   - **Solution:** Add cache plugin:
     ```
     docker { ttl 300 }
     cache 300
     ```

2. **TTL larger than cache:**
   ```
   # Bad
   docker { ttl 600 }
   cache 300
   
   # Good
   docker { ttl 300 }
   cache 300
   ```

3. **No CoreDNS cache at all:**
   - **Solution:** Always use cache for >50 containers

### Q: How to use with multiple Docker networks?

**Scenario:** Service connects to `app-network` and `monitoring-network`

**Solution 1 - Filter by network:**
```
docker {
    domain app.loc
    filter_network app-network  # Only use app-network IP
}
```

**Solution 2 - Label-based selection:**
```bash
docker run \
  --network app-network \
  --network monitoring-network \
  --label coredns.dockerdiscovery.network=app-network \
  my-service
```

### Q: Can I use both `network_aliases` and `filter_network`?

**Yes!** They serve different purposes:

```
docker {
    domain app.loc
    network_aliases prod-net    # Extract DNS names from aliases in prod-net
    filter_network prod-net     # Only register containers in prod-net
}
```

- `network_aliases` → what DNS names to create
- `filter_network` → which containers to register and which IP to use

### Q: Label resolver not working

**Check:**

1. **Label name is correct:**
   ```bash
   docker inspect my-container | grep Labels -A 10
   # Look for: "coredns.dockerdiscovery.host": "my-name.loc"
   ```

2. **Label resolver is always active** - no configuration needed:
   ```
   docker {
       # Label resolver works even without explicit config
   }
   ```

3. **Label value should be complete domain name:**
   ```bash
   # Correct
   --label coredns.dockerdiscovery.host=api.prod.loc
   
   # Wrong (no domain suffix will be added)
   --label coredns.dockerdiscovery.host=api
   ```

### Q: How to debug DNS resolution?

**Use dig to query CoreDNS directly:**

```bash
# Query specific DNS server
dig @localhost -p 15353 my-container.docker.loc

# Check TTL in response
dig @localhost -p 15353 my-container.docker.loc +noall +answer

# Trace query path
dig @localhost -p 15353 my-container.docker.loc +trace
```

**Check CoreDNS logs:**
```bash
# In Corefile
.:15353 {
    docker { domain docker.loc }
    log  # Enable logging
}

# Watch logs
docker logs -f coredns-container
```

### Q: Performance benchmarks?

**Latency without cache (from plugin):**
- 10 containers: ~2-5 microseconds
- 100 containers: ~20-50 microseconds  
- 1000 containers: ~100-500 microseconds

**Latency with cache:**
- Any number of containers: ~1-5 microseconds

**Throughput (single core):**
- < 50 containers: ~300K queries/sec (without cache)
- > 200 containers: ~3-4K queries/sec (without cache), ~200K with cache

**Recommendation:** Always use cache plugin for production deployments.

## Acknowledgements

This plugin is based on and inspired by [github.com/kevinjqiu/coredns-dockerdiscovery](https://github.com/kevinjqiu/coredns-dockerdiscovery.git) and [github.com/vOROn200/coredns-docker-discovery](https://github.com/vOROn200/coredns-docker-discovery). We thank the original authors for their valuable work.
