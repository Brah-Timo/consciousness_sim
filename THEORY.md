# THEORY.md — Scientific Foundations of consciousness_sim

## 1. Global Workspace Theory (GWT)

### Original Formulation
**Bernard Baars (1988)** proposed that consciousness operates like a "global
workspace" — a limited-capacity, shared broadcast medium that coordinates
specialised processors (perception, memory, motor control) which otherwise
operate in parallel isolation.

> "The global workspace is the neural correlate of the momentary contents of
> consciousness." — Baars, 1988

### Key Principles

| Principle | Description | Implementation |
|-----------|-------------|----------------|
| **Limited capacity** | Only ~7±2 items can be conscious at once (Miller, 1956) | `WorkspaceManager.capacity` |
| **Global broadcast** | The winning coalition broadcasts to all processors | `WorkspaceManager.broadcast()` |
| **Competition** | Multiple coalitions compete for workspace access | Salience scoring in `AttentionSpotlight` |
| **Ignition** | Non-linear threshold before broadcast | `attentionThreshold` parameter |
| **Reportability** | Only workspace contents are verbally reportable | `Consciousness.think()` |

---

## 2. Attention and the Spotlight Metaphor

### Treisman's Feature Integration Theory (1980)
Pre-attentive processing detects features in parallel; attentive processing
binds features serially within a spatial spotlight.

**Implementation:** `FeatureExtractor` performs the pre-attentive pass;
`AttentionSpotlight` applies serial resource allocation.

### Posner's Spotlight (1980)
Attention can be directed covertly (without eye movement) toward any location
in the representational space. Items outside the spotlight receive reduced
processing.

**Implementation:** `AttentionSpotlight.peripherySize` models the spotlight
penumbra; only the `primaryFocusId` concept receives full activation.

### Salience Formula
```
Salience(c) = (novelty × 0.25) + (relevance × 0.35)
            + (recency  × 0.20) + (emotion  × 0.20)
```
Inspired by itti-Koch saliency maps adapted to symbolic representations.

---

## 3. The Binding Problem

### Theoretical Background
The binding problem (Treisman & Gelade, 1980; Crick & Koch, 1990) asks:
how do distributed neural processes combine into unified conscious percepts?
For example, the redness, roundness, and sweetness of an apple are processed
in separate brain regions — what "glues" them together?

### Proposed Solutions
1. **Temporal synchrony**: Neurons bound together fire at the same gamma
   frequency (~40 Hz).
2. **Spatial convergence**: A master area receives convergent inputs.

### consciousness_sim Approach
We implement **temporal coincidence + semantic coherence** binding:

```
BindingStrength = (temporal_overlap × 0.30)
               + (semantic_similarity × 0.50)
               + (causal_cue_score × 0.20)
```

Cross-modal binding is handled by `CrossModalBinding` using the same
temporal window and token overlap.

---

## 4. Memory Architecture

### Tulving's Memory Taxonomy (1972, 1985)
- **Episodic memory**: "What happened to me" — specific events with context.
- **Semantic memory**: "What I know" — context-free world knowledge.

### Baddeley & Hitch Working Memory (1974)
- **Phonological loop**: Verbal rehearsal buffer.
- **Visuospatial sketchpad**: Visual imagery buffer.
- **Central executive**: Coordinates the sub-systems.
- **Episodic buffer** (added 2000): Integrates information from all sources.

**Implementation:** `WorkingMemory` models a unified short-term buffer (Cowan
2001: capacity ≈ 4±1 chunks).

### Ebbinghaus Forgetting Curve (1885)
```
S(t) = S₀ × e^(−t / τ)
```
where τ = halfLife / ln(2). Implemented in `Memory.applyDecay()`.

### Consolidation (Squire & Alvarez, 1995)
Long-term potentiation moves information from hippocampal (episodic) to
neocortical (semantic) storage. Modelled in `MemoryManager.consolidateMemories()`.

---

## 5. Reasoning and Inference

### Forward Chaining (Modus Ponens)
Classical rule-based AI reasoning:
```
IF conditions_met THEN conclusion
```
Implemented in `InferenceEngine._forwardChain()`.

### Causal Reasoning (Pearl, 2000)
Judea Pearl's causal graphical models distinguish:
- **Association**: A and B are correlated.
- **Intervention**: If we do A, what happens to B?
- **Counterfactual**: If A had not occurred, would B have happened?

`CausalInferenceEngine` implements the first level (association + temporal
ordering) as a practical approximation.

### Spreading Activation (Collins & Loftus, 1975)
In semantic networks, activation spreads from a node to its neighbours,
decaying with distance. Implemented in `ConceptualGraph.spreadActivation()`.

---

## 6. Coherence and Integration

### Information Integration Theory (IIT) — Tononi (2004)
Consciousness corresponds to the amount of integrated information (Φ) that
cannot be reduced to independent parts.

**Practical approximation:** Our `CoherenceManager` computes:
```
Coherence = (semantic × 0.45) + (temporal × 0.25)
           + (activation × 0.20) + (no_conflict × 0.10)
```

### Dehaene's Ignition Model (2001)
Consciousness = global "ignition" when a stimulus exceeds a threshold and
triggers a sudden non-linear broadcast to frontoparietal networks.

**Implementation:** `WorkspaceManager` eviction and `attentionThreshold`
model the ignition threshold dynamics.

---

## 7. Temporal Awareness

### Episodic Temporal Order
Humans remember not just what happened but when and in what order
(Conway, 2009). Concepts in consciousness_sim carry `creationTime`
timestamps; `CausalInferenceEngine` exploits temporal ordering to
distinguish likely causes from effects.

---

## 8. References

```
Baars, B. J. (1988). A cognitive theory of consciousness.
  Cambridge University Press.

Baddeley, A. D., & Hitch, G. (1974). Working memory.
  Psychology of Learning and Motivation, 8, 47–89.

Collins, A. M., & Loftus, E. F. (1975). A spreading-activation theory of
  semantic processing. Psychological Review, 82(6), 407–428.

Cowan, N. (2001). The magical number 4 in short-term memory.
  Behavioral and Brain Sciences, 24, 87–114.

Crick, F., & Koch, C. (1990). Towards a neurobiological theory of
  consciousness. Seminars in the Neurosciences, 2, 263–275.

Dehaene, S., Changeux, J. P., & Naccache, L. (2011). The Global Neuronal
  Workspace Model of Conscious Access. Neuron, 70(2), 201–227.

Ebbinghaus, H. (1885). Über das Gedächtnis. Duncker & Humblot.

Miller, G. A. (1956). The magical number seven, plus or minus two.
  Psychological Review, 63(2), 81–97.

Pearl, J. (2000). Causality: Models, reasoning, and inference.
  Cambridge University Press.

Posner, M. I. (1980). Orienting of attention. Quarterly Journal of
  Experimental Psychology, 32(1), 3–25.

Squire, L. R., & Alvarez, P. (1995). Retrograde amnesia and memory
  consolidation: A neurobiological perspective. Current Opinion in
  Neurobiology, 5(2), 169–177.

Tononi, G. (2004). An information integration theory of consciousness.
  BMC Neuroscience, 5, 42.

Treisman, A. M., & Gelade, G. (1980). A feature-integration theory of
  attention. Cognitive Psychology, 12(1), 97–136.

Tulving, E. (1972). Episodic and semantic memory. In E. Tulving & W. Donaldson
  (Eds.), Organization of memory. Academic Press.
```
