# Inference Engine

A high-performance, scalable neural network inference engine built in C++ with LibTorch, featuring containerization, auto-scaling, and production-ready deployment.

## 🚀 Features

- **High Performance**: Built with C++ and LibTorch for maximum inference speed
- **Batch Processing**: Intelligent request batching for optimal throughput
- **Model Hot-Swapping**: Load and unload models without server restart
- **RESTful API**: Easy-to-use HTTP endpoints for inference requests
- **Containerized**: Docker and Kubernetes ready with multi-stage builds
- **Auto-Scaling**: Kubernetes HPA configuration for dynamic scaling
- **Monitoring**: Built-in Prometheus metrics and health checks
- **Production Ready**: Comprehensive logging, error handling, and security

## 📋 Requirements

### System Requirements

- **OS**: Linux (Ubuntu 18.04+, CentOS 7+) or macOS 10.15+
- **Architecture**: x86_64 (Intel/AMD) or arm64 (Apple Silicon)
- **Memory**: 4GB RAM minimum, 8GB recommended
- **Storage**: 10GB free space
- **Network**: Internet connection for dependencies

### Software Dependencies

- CMake 3.18+
- GCC 8+ or Clang 8+
- Git
- Docker (optional)
- Python 3.7+ (for model creation)

## 🎯 Quick Start

### Option 1: Automated Installation (Recommended)

```bash
# Clone the repository
git clone <your-repo-url>
cd inference_engine

# Run the automated installer
chmod +x scripts/install_dependencies.sh
./scripts/install_dependencies.sh

# Build and run
./build.sh
./run.sh
```

### Option 2: Docker (Fastest)

```bash
# Clone and build
git clone <your-repo-url>
cd inference_engine

# Run with Docker Compose
docker-compose up --build

# Or build and run manually
docker build -t inference_engine .
docker run -p 8080:8080 inference_engine
```

### Option 3: Manual Installation

```bash
# Install system dependencies (Ubuntu/Debian)
sudo apt-get update && sudo apt-get install -y \
    build-essential cmake git pkg-config wget curl \
    unzip libomp-dev libssl-dev ca-certificates

# Download and install LibTorch
cd /opt
sudo wget https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-2.1.0%2Bcpu.zip
sudo unzip libtorch-cxx11-abi-shared-with-deps-2.1.0+cpu.zip

# Set environment variables
export CMAKE_PREFIX_PATH=/opt/libtorch:$CMAKE_PREFIX_PATH
export LD_LIBRARY_PATH=/opt/libtorch/lib:$LD_LIBRARY_PATH

# Build the project
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

## 🛠 Usage

### Starting the Server

```bash
# Development mode with hot reload
./dev.sh

# Production mode
./run.sh

# With custom configuration
./run.sh --config custom_config.json

# Docker development
docker-compose --profile dev up

# Docker production with monitoring
docker-compose --profile monitoring up -d
```

### API Endpoints

#### Health Check

```bash
curl http://localhost:8080/health
```

#### Load a Model

```bash
curl -X POST http://localhost:8080/models \
  -H "Content-Type: application/json" \
  -d '{
    "name": "resnet50",
    "path": "/app/models/resnet50.pt",
    "type": "classification"
  }'
```

#### Run Inference

```bash
# Image classification
curl -X POST http://localhost:8080/predict/resnet50 \
  -H "Content-Type: application/json" \
  -d '{
    "input": "base64_encoded_image_data",
    "format": "image"
  }'

# Batch inference
curl -X POST http://localhost:8080/predict/resnet50 \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [
      {"input": "image1_data", "format": "image"},
      {"input": "image2_data", "format": "image"}
    ]
  }'
```

#### Model Management

```bash
# List loaded models
curl http://localhost:8080/models

# Unload a model
curl -X DELETE http://localhost:8080/models/resnet50

# Model statistics
curl http://localhost:8080/models/resnet50/stats
```

### Monitoring

- **Metrics**: http://localhost:9090/metrics (Prometheus format)
- **Grafana**: http://localhost:3000 (admin/admin)
- **Health**: http://localhost:8080/health

## ⚙️ Configuration

### Server Configuration (`config/server.json`)

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 8080,
    "worker_threads": 4,
    "request_timeout_ms": 30000
  },
  "inference": {
    "max_batch_size": 8,
    "batch_timeout_ms": 10,
    "enable_batching": true,
    "device": "cpu"
  },
  "models": {
    "model_directory": "./models",
    "default_models": [
      {
        "name": "resnet50",
        "path": "./models/resnet50.pt",
        "type": "classification",
        "enabled": true
      }
    ]
  }
}
```

### Environment Variables

```bash
# Server configuration
export LOG_LEVEL=info
export WORKER_THREADS=4
export MAX_BATCH_SIZE=8
export BATCH_TIMEOUT_MS=10

# LibTorch paths
export CMAKE_PREFIX_PATH=/opt/libtorch
export LD_LIBRARY_PATH=/opt/libtorch/lib
```

## 🏗 Project Structure

```
inference_engine/
├── src/                    # Source code
│   ├── core/              # Core inference engine
│   ├── serving/           # HTTP server and API
│   └── utils/             # Utilities and helpers
├── include/               # Header files
├── config/                # Configuration files
│   └── server.json        # Main server config
├── models/                # Model storage
│   └── resnet50.pt        # Sample model
├── scripts/               # Helper scripts
│   ├── install_dependencies.sh
│   └── setup_env.sh
├── k8s/                   # Kubernetes manifests
│   └── deployment.yaml
├── monitoring/            # Monitoring configs
├── logs/                  # Log files
├── build/                 # Build output
├── tests/                 # Test files
├── CMakeLists.txt         # Build configuration
├── Dockerfile             # Container definition
├── docker-compose.yml     # Multi-service setup
├── Makefile              # Build automation
└── README.md             # This file
```

## 🔧 Development

### Building from Source

```bash
# Debug build
./build.sh Debug

# Release build
./build.sh Release

# With custom options
./build.sh Release 8  # 8 parallel jobs

# Using Make directly
make build
make clean
make rebuild
```

### Development Workflow

```bash
# Start development server with hot reload
./dev.sh

# Run tests
./test.sh

# Code formatting
make format

# Static analysis
make lint

# Generate documentation
make docs
```

### Adding Custom Models

1. **Prepare your PyTorch model**:

```python
import torch

# Your model
model = YourModel()
model.eval()

# Trace for inference
example_input = torch.randn(1, 3, 224, 224)
traced_model = torch.jit.trace(model, example_input)
traced_model.save('your_model.pt')
```

2. **Add to configuration**:

```json
{
  "name": "your_model",
  "path": "./models/your_model.pt",
  "type": "classification",
  "enabled": true,
  "preprocessing": {
    "input_size": [224, 224],
    "normalize": {
      "mean": [0.485, 0.456, 0.406],
      "std": [0.229, 0.224, 0.225]
    }
  }
}
```

3. **Load via API**:

```bash
curl -X POST http://localhost:8080/models \
  -H "Content-Type: application/json" \
  -d @your_model_config.json
```

## 🐳 Docker Usage

### Development

```bash
# Development with hot reload
docker-compose --profile dev up

# Rebuild and start
docker-compose up --build

# View logs
docker-compose logs -f
```

### Production

```bash
# Production deployment
docker-compose --profile production up -d

# With monitoring stack
docker-compose --profile monitoring up -d

# Scale inference service
docker-compose up --scale inference-engine=3
```

### Custom Docker Build

```bash
# Build specific stage
docker build --target builder -t inference-builder .
docker build --target runtime -t inference-engine .

# Multi-platform build
docker buildx build --platform linux/amd64,linux/arm64 -t inference-engine .
```

## ☸️ Kubernetes Deployment

### Quick Deploy

```bash
# Deploy to Kubernetes
make k8s-deploy

# Check status
make k8s-status

# View logs
make k8s-logs

# Scale deployment
kubectl scale deployment inference-engine --replicas=5
```

### Custom Deployment

```bash
# Apply manifests
kubectl apply -f k8s/

# Monitor rollout
kubectl rollout status deployment/inference-engine

# Port forward for testing
kubectl port-forward svc/inference-service 8080:80
```

### Auto-Scaling

The deployment includes Horizontal Pod Autoscaler (HPA):

```yaml
# Scales based on CPU/Memory usage
minReplicas: 2
maxReplicas: 10
targetCPUUtilization: 70%
targetMemoryUtilization: 80%
```

## 📊 Performance

### Benchmarks

| Model    | Batch Size | Latency (ms) | Throughput (req/s) |
| -------- | ---------- | ------------ | ------------------ |
| ResNet50 | 1          | 50           | 20                 |
| ResNet50 | 8          | 200          | 40                 |
| ResNet50 | 16         | 400          | 40                 |

### Optimization Tips

1. **Batch Processing**: Enable batching for higher throughput
2. **Worker Threads**: Set to number of CPU cores
3. **Memory**: Ensure sufficient RAM for model loading
4. **Storage**: Use fast SSD for model files
5. **Network**: Use load balancer for multiple instances

## 🔍 Troubleshooting

### Common Issues

#### Build Failures

```bash
# Check LibTorch installation
ls -la /opt/libtorch/lib/

# Verify environment
source scripts/setup_env.sh
echo $CMAKE_PREFIX_PATH

# Clean build
make clean && make build
```

#### Runtime Errors

```bash
# Check logs
tail -f logs/inference.log

# Test health endpoint
curl http://localhost:8080/health

# Verify model files
ls -la models/
```

#### Docker Issues

```bash
# Check container logs
docker-compose logs inference-engine

# Rebuild without cache
docker-compose build --no-cache

# Check resource usage
docker stats
```

### Performance Issues

1. **High Latency**:

   - Check batch timeout settings
   - Verify CPU/memory resources
   - Monitor system load

2. **Low Throughput**:

   - Increase batch size
   - Add more worker threads
   - Scale horizontally

3. **Memory Issues**:
   - Reduce batch size
   - Implement model caching
   - Monitor memory usage

## 🤝 Contributing

### Development Setup

```bash
# Fork and clone the repository
git clone <your-fork-url>
cd inference_engine

# Install development dependencies
./scripts/install_dependencies.sh

# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
./build.sh Debug
./test.sh

# Submit pull request
```

### Code Style

- Follow Google C++ Style Guide
- Use `clang-format` for formatting
- Add tests for new features
- Update documentation

### Testing

```bash
# Run all tests
make test

# Run specific test suite
./build/tests/unit_tests

# Coverage report
make coverage
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [PyTorch](https://pytorch.org/) for LibTorch
- [Crow](https://github.com/CrowCpp/Crow) for HTTP server
- [nlohmann/json](https://github.com/nlohmann/json) for JSON parsing
- [spdlog](https://github.com/gabime/spdlog) for logging

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/inference_engine/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/inference_engine/discussions)
- **Documentation**: [Wiki](https://github.com/your-org/inference_engine/wiki)

---

**Built with ❤️ for high-performance AI inference**
