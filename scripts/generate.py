import jinja2
import itertools
import sys

# Possible values for each parameter
flavors = ["gcc", "go", "rust"]
architectures = ["amd64", "arm64", "arm"]
osnames = ["numbat", "jammy"]  # Example OS names
osversions = {"numbat": "2404", "jammy" : "2204"}  # Example OS names
dind_options = [True, False]  # dind enabled or not

# Static values
githubConfigUrl = "https://github.com/nubificus"
github_pat = "982298"

# Generate all combinations of arch, osversion, osname, and dind
combinations = list(itertools.product(flavors, architectures, osnames, dind_options))

# Initialize an empty list to hold the data dictionaries
data_list = []

# Loop through the combinations and generate the data dictionaries
for flavor, arch, osname, dind in combinations:
    runner_image = f"{osname}-{flavor}"
    data = {
        "architecture": arch,
        "runner_image": runner_image,
        "dind": dind,
        "githubConfigUrl": githubConfigUrl,
        "github_pat": github_pat,
        "osname": osname,
        "osversion": osversions[osname],
        "flavor": flavor,
        "k8s_secret": "pre-defined-secret"
    }
    data_list.append(data)

# Print the generated data dictionaries
for data in data_list:
    print(data)

# Load the Jinja2 template
template_loader = jinja2.FileSystemLoader(searchpath="./templates")
template_env = jinja2.Environment(loader=template_loader)
template_file = "template.j2"
template = template_env.get_template(template_file)

if len(sys.argv) > 1: 
    if sys.argv[1] == 'uninstall':
    # Loop through the generated data dictionaries and generate YAML & Helm commands for each set
        for data in data_list:
 
            strdind = ""
            if data['dind']:
                strdind = "-dind"

            installation_name = f"{data['flavor']}{strdind}-{data['osversion']}-{data['architecture']}"
            namespace = "arc-runners"
 
            helm_command = f"helm uninstall \"{installation_name}\" --namespace \"{namespace}\""
            # Print the Helm command for installation
            print(f"{helm_command}")
        exit(0)

# Loop through the generated data dictionaries and generate YAML & Helm commands for each set
for data in data_list:
    if data['architecture'] == 'arm' and data['flavor'] == 'go':
        continue
    # Render the template for each data set
    output = template.render(data)
    
    strdind = ""
    if data['dind']:
        strdind = "-dind"
    # Generate the YAML filename
    yaml_filename = f"values{strdind}-{data['architecture']}-{data['runner_image']}.yaml"
    with open(yaml_filename, 'w') as file:
        file.write(output)
    
    #print(f"YAML file generated: {yaml_filename}")

    # Generate Helm installation command for each data set
    installation_name = f"{data['flavor']}{strdind}-{data['osversion']}-{data['architecture']}"
    namespace = "arc-runners"

    helm_command = f"""
helm install "{installation_name}" \\
    --namespace "{namespace}" \\
    --create-namespace \\
    --set githubConfigUrl="{data['githubConfigUrl']}" \\
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set -f {yaml_filename}
"""

    # Print the Helm command for installation
    #print(f"Helm install command: \n{helm_command}")
    print(f"{helm_command}")
