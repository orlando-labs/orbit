package orbit.release.prepare

export main

def absolute(path, base):
  fs.Path(if path.starts_with?("/") then path else base + "/" + path).normalize.to_str

def scoped(name):
  if name == "orbit" or name.starts_with?("orbit.") or name == "orm" or name.starts_with?("orm."):
    return "slowpilot." + name
  name

def qualify(line):
  declaration = r"^([ \t]*)(package|from|import) ([\w.]+)(.*)$".match(line)
  return line unless declaration
  name = declaration[3]
  qualified = scoped(name)
  return line if qualified == name
  tail = declaration[4]
  if declaration[2] == "import" and tail.trim == "":
    tail = " as " + name.split(".").last
  declaration[1] + declaration[2] + " " + qualified + tail

def stage_sources(directory, stage, files, modules):
  paths = fs.entries(directory).map: $it.to_str
  paths.sorted.each |path|:
    metadata = fs.metadata(path)
    leaf = fs.Path(path).basename
    if leaf.starts_with?(".") or metadata.symlink?:
      next
    if metadata.dir?:
      stage_sources(path, stage, files, modules)
    elif metadata.file? and leaf.ends_with?(".s"):
      source = fs.read_text(path)
      declaration = r"^package ([A-Za-z_][\w.]*)$"m.match(source)
      unless declaration:
        raise ValueError("Source has no package declaration: " + path)
      module = scoped(declaration[1])
      if modules.include?(module):
        raise ValueError("Duplicate release module: " + module)
      modules.push!(module)
      relative = "src/" + module.replace(".", "/") + ".s"
      destination = stage + "/" + relative
      fs.mkdir_p(fs.Path(destination).parent)
      lines = r"\n".split(source, keep_empty: true).map: qualify($it)
      fs.atomic_write_text(destination, lines.join("\n"))
      files.push!(relative)

def run(tool, args, log):
  result = system.command(tool, *args).capture(timeout: 180.0, check: false)
  fs.atomic_write_bytes(log, result.stdout)
  unless result.success?:
    raise ValueError("Release command failed. See " + log + "\n" + result.stderr.to_str)
  result.stdout.to_str

def check_sdk(tool, sdk):
  version = system.command(tool, "--version").output(timeout: 10.0).trim
  header = fs.read_text(sdk + "/runtime/version.h")
  parts = ["MAJOR", "MINOR", "PATCH"].map |part|:
    match = Regexp.compile("^#define SPUTNIK_VERSION_" + part + " ([0-9]+)$", multiline: true).match(header)
    unless match:
      raise ValueError("Incomplete Sputnik SDK version header")
    match[1]
  unless version == "sputnik " + parts.join("."):
    raise ValueError("Sputnik compiler and SDK headers differ")

def scope_board(value, provider):
  if Map === value:
    reference = value[?"package_component"]
    if Map === reference and reference[?"provider"] == provider:
      reference["provider"] = "slowpilot/" + provider
    value.each |key, child|: scope_board(child, provider)
  elif Array === value:
    value.each |child|: scope_board(child, provider)

def stage_notebook(root, stage, provider, files):
  path = "notebook/components.json"
  descriptor = Json.parse(fs.read_text(root + "/" + path))
  boards = {}
  assets = []
  descriptor["components"].each |component|:
    if component[?"module"]:
      component["module"] = scoped(component["module"])
    if component[?"board"]:
      boards[component["board"]] = true
    (component[?"board_assets"] or {}).each |destination, member|:
      if not assets.include?(member): assets.push!(member)
  assets.each |member|:
    stage_notebook_member(root, stage, member, files, transform: false, provider: provider)
  boards.keys.each |member|:
    stage_notebook_member(root, stage, member, files, transform: true, provider: provider)
  fs.mkdir_p(stage + "/notebook")
  fs.atomic_write_text(stage + "/" + path, Json.pretty_generate(descriptor) + "\n")
  files.push!(path)

def stage_notebook_member(root, stage, member, files, transform:, provider:):
  if not r"notebook/[A-Za-z0-9_./-]+".full_match?(member) or member.contains?("..") or files.include?(member):
    raise ValueError("Invalid or duplicate Notebook asset: " + member)
  destination = stage + "/" + member
  fs.mkdir_p(fs.Path(destination).parent)
  if transform:
    board = Json.parse(fs.read_text(root + "/" + member))
    scope_board(board, provider)
    fs.atomic_write_text(destination, Json.pretty_generate(board) + "\n")
  else:
    fs.atomic_write_bytes(destination, fs.read_bytes(root + "/" + member))
  files.push!(member)

def main():
  parser = ArgParser(name: "Prepare an Orbit package")
  parser.arg("--release", required: true)
  parser.arg("--sdk", required: true)
  parser.arg("--config", default: "package.json")
  parser.arg("--sputnik")
  parser.arg("--out", default: "out")
  parser.arg("--modules", choices: ["source", "bytecode", "mixed"], default: "source")
  args = parser.parse_or_raise()
  release = args[:release]
  repo = fs.Path(release).parent.to_str
  compiler = absolute(args[:sputnik] or args[:sdk] + "/build/sputnik", repo)
  check_sdk(compiler, args[:sdk])
  config_path = args[:config]
  config = Json.parse(fs.read_text(absolute(config_path, release)))
  package_name = config["name"]
  unless r"[a-z][a-z0-9-]*".full_match?(package_name):
    raise ValueError("Invalid release package name")
  variant = args[:modules]
  work = absolute(args[:out], release) + "/" + package_name + "/" + variant
  stage = work + "/stage"
  fs.mkdir_p(stage)
  files = []
  modules = []
  config["source_roots"].each |directory|:
    unless r"[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*".full_match?(directory):
      raise ValueError("Source roots must be relative package directories")
    stage_sources(repo + "/" + directory, stage, files, modules)
  root_module = scoped(config["root"])
  unless modules.include?(root_module):
    raise ValueError("Release is missing its root module " + root_module)
  package_root = absolute(config[?"package_root"] or ".", repo)
  if config[?"notebook_components"]:
    stage_notebook(package_root, stage, package_name, files)
  ["LICENSE", "README.md", "API.md"].each |name|:
    document = package_root + "/" + name
    document = repo + "/LICENSE" if name == "LICENSE" and not fs.exists?(document)
    if fs.exists?(document) and fs.file?(document):
      fs.atomic_write_bytes(stage + "/" + name, fs.read_bytes(document))
      files.push!(name)
  dependencies = {}
  (config[?"dependencies"] or {}).each |name, version|:
    dependencies["slowpilot/" + name] = version
  manifest = {
    schema: "sputnik.build.v1",
    name: "slowpilot/" + package_name,
    version: config["version"],
    requires: config["requires"],
    source_root: "src",
    files: files.sorted,
    dependencies: dependencies,
    capabilities: config[?"capabilities"] or {},
    notebook_packages: config[?"notebook_packages"] or [],
    artifact: {variant: variant}
  }
  fs.atomic_write_text(stage + "/sputnik.build.json", Json.pretty_generate(manifest) + "\n")
  archive = work + "/" + package_name + "-" + variant + ".sputnikpkg"
  run(compiler, ["pkg", "build", stage, "--modules", variant, "--out", archive], work + "/build.json")
  report = Json.parse(run(compiler, ["pkg", "inspect", archive], work + "/inspect.json"))
  if variant == "mixed" and report["bytecode_modules"] == 0:
    fs.remove(archive)
    print("Skipped redundant mixed variant with no bytecode modules")
  else:
    print(archive)
