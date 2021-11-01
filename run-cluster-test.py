#!/usr/bin/python3
import json
import os
import socket
import subprocess
import sys
import datetime

import client as rapi
import random
import tempfile
import argparse

DOMAIN = "staging.ganeti.org"
INSTANCE_NAMES = [
    'bart',
    'lisa',
    'homer',
    'marge',
    'maggie',
    'milhouse',
    'krusty',
    'frink',
    'kodos',
    'kang',
    'grandpa',
    'moe',
    'mr-burns',
    'smithers',
    'flanders',
    'radioactive-man',
    'maude-flanders',
    'lenny',
    'carl',
    'willy',
    'barney',
    'blinky',
    'bumble-bee-man',
    'patty',
    'selma',
    'kent-brockman',
    'duffman',
    'fat-tony',
    'fallout-boy',
    'rod-flanders',
    'todd-flanders',
    'herman',
    'julius-hibbert',
    'lionel-hutz',
    'itchy',
    'scratchy',
    'timothy-lovejoy',
    'otto',
    'mcbain',
    'troy-mcclure',
    'nelson-muntz',
    'jimbo-jones',
    'dolph-starbeam',
    'apu',
    'sideshow-bob',
    'major-quimby',
    'principal-skinner',
    'snake',
    'clancy-wiggum',
    'ralph-wiggum',
    'cletus',
    'spider-pig',
    'disco-stu'
]
ADJECTIVES = [
    'abnormal',
    'agile',
    'amazing',
    'ambitious',
    'amusing',
    'artistic',
    'average',
    'awesome',
    'awful',
    'balanced',
    'beautiful',
    'blunt',
    'brave',
    'bright',
    'brilliant',
    'candid',
    'capable',
    'careful',
    'careless',
    'cautious',
    'charming',
    'cheerful',
    'childish',
    'civil',
    'clean',
    'clever',
    'clumsy',
    'coherent',
    'cold',
    'competent',
    'composed',
    'confident',
    'confused',
    'cordial',
    'crafty',
    'cranky',
    'crass',
    'critical',
    'cruel',
    'curious',
    'cynical',
    'dainty',
    'decisive',
    'delicate',
    'demonic',
    'devoted',
    'direct',
    'discreet',
    'distant',
    'dramatic',
    'drowsy',
    'drunk',
    'dull',
    'dutiful',
    'eager',
    'earnest',
    'efficient',
    'emotional',
    'energetic',
    'evasive',
    'fabulous',
    'fervent',
    'flaky',
    'friendly',
    'funny',
    'generous',
    'gentle',
    'gloomy',
    'grave',
    'great',
    'groggy',
    'hateful',
    'helpful',
    'hesitant',
    'idiotic',
    'idle',
    'impulsive',
    'inactive',
    'inventive',
    'keen',
    'kind',
    'lame',
    'lazy',
    'lean',
    'lethargic',
    'lively',
    'logical',
    'lovable',
    'lovely',
    'mature',
    'mean',
    'mild',
    'modest',
    'naive',
    'nasty',
    'natural',
    'negative',
    'nervous',
    'noisy',
    'normal',
    'nosy',
    'numb',
    'passive',
    'plain',
    'playful',
    'pleasant',
    'plucky',
    'polite',
    'popular',
    'positive',
    'powerful',
    'pretty',
    'proud',
    'prudent',
    'punctual',
    'quick',
    'quiet',
    'realistic',
    'sad',
    'sassy',
    'selfish',
    'sensible',
    'shy',
    'silly',
    'sincere',
    'sleepy',
    'sloppy',
    'slow',
    'smart',
    'snobby',
    'sober',
    'stable',
    'steady',
    'stoic',
    'striking',
    'strong',
    'stupid',
    'sturdy',
    'subtle',
    'sulky',
    'sullen',
    'surly',
    'sweet',
    'tactful',
    'tactless',
    'talented',
    'timid',
    'tired',
    'tolerant',
    'touchy',
    'ugly',
    'unsure',
    'vigilant',
    'warm',
    'wary',
    'weak',
    'willing',
    'wonderful',
    'zealous',
]

CLUSTER_IP_MIN = 240
CLUSTER_IP_MAX = 254

STATE_FILE = "%s/runs.json" % (os.path.dirname(os.path.realpath(__file__)))

def get_random_adjective():
    return random.choice(ADJECTIVES)


def get_random_instance_name():
    return random.choice(INSTANCE_NAMES)


def generate_instance_names(amount):
    names = []
    for i in range(amount):
        name_accepted = False
        break_counter = 0
        while not name_accepted:
            break_counter = break_counter + 1
            if break_counter > 40:
                raise Exception("Error: no available instance names left. Check unused/dangling instances!")

            name = get_random_instance_name()
            fqdn = "%s.%s" % (name, DOMAIN)

            if fqdn in names:
                continue

            if not instance_exists(fqdn):
                names.append(fqdn)
                name_accepted = True
    return names


def read_stored_runs():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def store_runs(runs):
    with open(STATE_FILE, 'w') as f:
        json.dump(runs, f)


def get_cluster_ip():
    ips_in_use = []
    for name in runs:
        ips_in_use.append(runs[name]["cluster-ip"])

    for i in range(CLUSTER_IP_MIN, CLUSTER_IP_MAX):
        ip = "192.168.1.%s" % (i)
        if ip not in ips_in_use:
            return ip

    raise Exception("Error: cannot allocate cluster IP address. Please check runs.json!")


def store_recipe(recipe_name, nodes):
    temp_file = tempfile.NamedTemporaryFile(delete=False, mode="w")

    qa_file_name = "qa-configs/%s.json" % recipe_name
    with open(qa_file_name) as f:
        recipe = json.load(f)

    node_list = []
    for node in nodes:
        node_list.append({
            "primary": node,
            "secondary": socket.gethostbyname(node)
        })

    recipe["nodes"] = node_list

    json.dump(recipe, temp_file)

    return temp_file.name


def store_inventory(names):
    temp_file = tempfile.NamedTemporaryFile(delete=False)

    inventory_file_content = """[ganeti_nodes:children]
master_node
non_master_nodes

[master_node]
%s

[non_master_nodes]
%s
%s
""" % (names[0], names[1], names[2])

    inv_bytes = bytearray(inventory_file_content, "utf-8")
    temp_file.write(inv_bytes)
    temp_file.close()

    return temp_file.name


def scp_file(source_path, dest_path, target_host):
    cmd = [
        "/usr/bin/scp",
        source_path,
        "root@%s:%s" % (target_host, dest_path)
    ]

    print("Running '%s'" % " ".join(cmd))

    subprocess.run(cmd, check=True)


def run_remote_cmd(command, target_host):
    cmd = [
        "/usr/bin/ssh",
        "root@%s" % target_host,
        command
    ]

    print("Running '%s'" % " ".join(cmd))

    subprocess.run(cmd, check=True)


def run_ansible_playbook(inventory_file, extra_vars, recipe):

    cmd = [
        "ansible-playbook",
        "-u",
        "root",
        "-i",
        inventory_file,
        "-e",
        extra_vars,
        "%s.yml" % recipe
    ]

    print("Running '%s'" % " ".join(cmd))

    subprocess.run(cmd, check=True)


def init_rapi():
    return rapi.GanetiRapiClient("localhost", port=5080, username="rapi", password="gnt-build-setup")


def instance_exists(name):
    try:
        client.GetInstance(name)
    except rapi.GanetiApiError as e:
        if e.code == 404:
            return False
        else:
            raise
    return True


def create_instance(name, os_type, tag):
    params = {
        '__version__': 1,
        'beparams': {
            'memory': "6G",
            'minmem': "6G",
            'maxmem': "6G",
            'vcpus': 4,
        },
        'disk_template': "plain",
        'disks': [
            {
                'size': "10G"
            },
            {
                'size': "22G"
            }
        ],
        'nics': [
            {
                'network': 'staging',
                'ip': 'pool'
            }
        ],
        'hypervisor': "kvm",
        'iallocator': "hail",
        'name': name,
        'os_type': "debootstrap+" + os_type,
        'mode': 'create',
        'conflicts_check': False,
        'ip_check': False,
        'name_check': False,
        'tags': [
            tag
        ],
    }
    job_id = client.CreateInstance(**params)
    if not client.WaitForJobCompletion(job_id, period=1):
        job = client.GetJobStatus(job_id)
        raise Exception("Failed to create instance %s: %s" % (name, job["opresult"]))


def remove_instances_by_tag(tag):
    result = client.Query("instance", ["name", "tags"])
    for data in result["data"]:
        if tag in data[1][1]:
            instance = data[0][1]
            job_id = client.ShutdownInstance(instance, timeout=0)
            if not client.WaitForJobCompletion(job_id, period=1):
                job = client.GetJobStatus(job_id)
                raise Exception("Failed to shutdown instance %s: %s" % (instance, job["opresult"]))
            job_id = client.DeleteInstance(instance)
            if not client.WaitForJobCompletion(job_id, period=1):
                job = client.GetJobStatus(job_id)
                raise Exception("Failed to remove instance %s: %s" % (instance, job["opresult"]))


def get_instances_by_tag():
    result = client.Query("instance", ["name", "tags"])
    instances = {}
    for data in result["data"]:
        if len(data[1][1]) == 1:
            first_tag = data[1][1][0]
            if first_tag not in instances:
                instances[first_tag] = []
            instances[first_tag].append(data[0][1])
        else:
            if "NO_TAG_AVAILABLE" not in instances:
                instances["NO_TAG_AVAILABLE"] = []
            instances["NO_TAG_AVAILABLE"].append(data[0][1])
    return instances


def main():
    global client
    client = init_rapi()


    parser = argparse.ArgumentParser(description="Manage Ganeti Cluster testing environments")
    parser.add_argument('mode', choices=["remove-tests", "run-test", "list-tests"])
    parser.add_argument('--source', default="ganeti/ganeti")
    parser.add_argument('--branch', default="master")
    parser.add_argument('--os-version', default=None)
    parser.add_argument('--recipe', default=None)
    parser.add_argument('--tag', default=None)
    parser.add_argument('--remove-instances-on-success', action='store_true', default=False)
    parser.add_argument('--build-only', action='store_true', default=False)

    args = parser.parse_args()

    # parameter validation
    if args.mode == "run-test":
        if args.os_version is None:
            print("Error: please specify the OS version (e.g. buster) to run a test")
            sys.exit(1)
        if args.recipe is None:
            print("Error: please specify the test recipe to use (e.g. kvm-drbd_file_sharedfile-bridged) to run a test")
            sys.exit(1)
        else:
            if not os.path.exists("%s.yml" % args.recipe):
                print("Error: the given recipe does not seem to exist (make sure there is an Ansible playbook with "
                      "the same name in this directory)")
                sys.exit(1)
    elif args.mode == "remove-tests":
        if args.tag is None:
            print("Error: Please specify a valid tag for 'remove-tests' mode")
            sys.exit(1)

    global runs
    runs = read_stored_runs()
    cluster_ip = get_cluster_ip()

    # operational logic
    if args.mode == "run-test":
        tag = "%s-%s" % (get_random_adjective(), get_random_instance_name())
        print("Using tag '%s' for this session" % tag)
        runs[tag] = {
            "cluster-ip": cluster_ip,
            "type": args.recipe
        }
        store_runs(runs)
        instances_start = datetime.datetime.now()
        instances = generate_instance_names(3)
        for instance in instances:
            print("Creating instance %s... " % instance, end="")
            create_instance(instance, args.os_version, tag)
            print("done.")
        instances_end = datetime.datetime.now()

        inventory_file = store_inventory(instances)
        extra_vars = "ganeti_source=%s ganeti_branch=%s ganeti_cluster_ip=%s" % (args.source, args.branch, cluster_ip)
        playbook_start = datetime.datetime.now()
        run_ansible_playbook(inventory_file, extra_vars, args.recipe)
        playbook_end = datetime.datetime.now()

        if args.build_only:
            print("Finished setting up the cluster, but --build-only was given. Exiting now!")
            sys.exit()

        src_file = store_recipe(args.recipe, instances)
        scp_file(src_file, "/tmp/recipe.json", instances[0])

        qa_command = "export PYTHONPATH=\"/usr/src/ganeti:/usr/share/ganeti/default\"; cd /usr/src/ganeti/qa; python3 -u ganeti-qa.py --yes-do-it /tmp/recipe.json"
        qa_start = datetime.datetime.now()
        run_remote_cmd(qa_command, instances[0])
        qa_end = datetime.datetime.now()

        if args.remove_instances_on_success:
            print("")
            print("QA finished successfully - removing test instances")
            print("")
            remove_instances_by_tag(tag)
            runs = read_stored_runs()
            del runs[tag]
            store_runs(runs)

        instances_diff = instances_end - instances_start
        playbook_diff = playbook_end - playbook_start
        qa_diff = qa_end - qa_start

        print("Instance Creation Runtime: {}".format(instances_diff))
        print("Setup/Playbook Runtime: {}".format(playbook_diff))
        print("QA Suite Runtime: {}".format(qa_diff))
        print("")
        print("Overall Runtime: {}".format(instances_diff + playbook_diff + qa_diff))

    elif args.mode == "remove-tests":
        print("Removing all instances from the cluster with the tag '%s'" % args.tag)
        remove_instances_by_tag(args.tag)

    elif args.mode == "list-tests":
        print("Listing all instances grouped by tag")
        print(get_instances_by_tag())


if __name__ == "__main__":
    main()
