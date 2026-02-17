# Run OHB in a docker container

We always recommend using one of the cloud-based backends. There is load created on the many services hamclock uses to populate it's data. The OHB caches that data and serves it up to the many hamclock deployments.

But if you want to run your own OHB (for example you are an early adopter and don't want to wait for the cloud-based backends to be deployed), then install your own OHB.

Of course OHB can be deployed on a host OS. But there are many distributions out there and potentially the OHB dependencies can cause issues with your system. The generally accepted method of managing this is to run the service in a container.

You haven't used docker before? Now's your chance! It's not hard and it's great experience.

## What's a docker deployment?

To get OHB to run in docker on your machine, you'll need to:
- install docker on your machine (some distributions like Ubuntu 24.04 install very old docker so you might need to set up the docker repository)
- get the OHB manager for docker
- launch the container with the OHB manager

## Where are the docker images?

We maintain docker images for the releases in Docker Hub. When you launch your container it will automatically pull the image from Docker Hub. If you built the image yourself (with the build scripts), it will use yours.

The build scripts let you create your own image. You might want to do this if you want to run bleeding edge code. Or maybe you just want to host your own.

## Install docker
We'll consider installing docker a little outside the scope of this readme. It can be os dependent so look up instructions for your distribution.

The main consideration is that you have a recent version and you have docker compose installed.

At the time of this writing my docker and docker compose versions are:
```
$ dockerd -v
Docker version 29.2.0, build 1.fc43
$ docker compose version
Docker Compose version 5.0.2
```

Your version could be a little bit older. However a clue that your version is very old (too old!) is, for example, docker compose version in the 1.x range.

Be sure you have a recent docker and docker compose installed before proceeding.

# Install OHB with official images
## The steps if I want to use the official image from Docker Hub

Either get the source tree from GitHub or download the manage-ohb-docker.sh script. Getting the source tree is only necessary if you plan to build your own custom image, which is covered down below.

### option 1: download the manager:
Find the tag you want from git:
```
https://github.com/BrianWilkinsFL/open-hamclock-backend/tags
```
Navigate into the tag, download from ```Manage Docker Installs``` which will get you a file named: ```manage-ohb-docker.sh```, and make it executable. Using curl might work like this for v1.0:
```
curl -sO 
https://github.com/BrianWilkinsFL/open-hamclock-backend/releases/download/v1.0/manage-ohb-docker.sh
chmod +x manage-ohb-docker.sh
```

### option 2: get the GitHub source tree
The git clone command below should have the right URL but you can check it by visiting https://github.com/BrianWilkinsFL/open-hamclock-backend, click on the green "Code" button and copy the https url.

On your computer, clone the repository:
```
git clone https://github.com/BrianWilkinsFL/open-hamclock-backend.git
```

Go into the project's docker directory:
```
cd open-hamclock-backend/docker
```

Ensure you are on the release you want to build. For example:
```
git tag # lists the available tags
git checkout v1.0
```

## Run the manager
Check out options with help:
```
# the help outputs options
./manage-ohb-docker.sh help
```

Double check your docker version:
```
./manage-ohb-docker.sh check-docker
```

Do an install. Note that if you are running it from a git checkout, it will use the git tag or branch name. If you are running it standalone you should provide it the tag you want to install. It defaults to ```latest```:

```
./manage-ohb-docker.sh install -t v1.0
```

When the script is done, you should have a running install of OHB! Try this:
```
# insert your ip address:
curl -s http://127.0.0.1/ham/HamClock/version.pl
```

If it's the first time you've run it, it can take a while to populate the data. Nearly all of the current data should be ready in around 60 minutes depending on internet speed. In some cases history has to accumulate for all the graphs to look right which could take days. But while you wait days, you'll have a fully functioning hamclock with your own custom OHB.

You can track the data seeding process like this:
```
# ^C to get out
docker logs -f open-hamclock-backend
```


## Point your hamclock to your new back end

Go to the project readme and look for information about the '-b' otion to hamclock. This will make your hamclock pull its data from your OHB.

# Install OHB with your own image
## The steps if you want to create your own image
You'll need a git checkout of the version you want to build. See above for getting a git clone and checkout.

The build-image.sh utility will create an image for you based on the git branch you have checked out. If you aren't on a git tag, the resulting image will be tagged 'latest':
```
./build-image.sh
```

# Upgrades
Upgrading OHB is easy. Basically run the manager utility with upgrade. Like the install, it will default to the git tag if there is one, or fall back to latest. You should provide the tag you want to upgrade to if the default isn't what you want:
```
./manage-ohb-docker.sh upgrade -t v1.0
```

The data is persisted in the storage space you created in the first install. It will have the history after you upgrade. If there are new features, possibly those could take a while to populate. It just depends on the feature.

# Your hamclock
Ok, so you have a back end. But does your hamclock know about it? Go to the project readme and look for information about the '-b' otion to hamclock.


# API Keys
Two services require API keys: openweathermaps.com and ipgeolocation.io.

If openweathermaps doesn't get a key, HamClock will fall back to open-meteo.com. If ipgeolocation.io doesn't have a key, installinga new HamCLock won't be able to pull up your location. Not the end of the world.

If you have these keys, you can provide them to OHB by putting them into a file named ```.env``` and formatting the contents like this:
```
# for the api.openweathermap.org API
OPEN_WEATHER_API_KEY=<insert key here>

# for the app.ipgeolocation.io API
IPGEOLOC_API_KEY=<insert key here>
```
Replace \<insert key here\> with your respective key.

Upon a fresh install or upgrade, the file will be used automatically. To add the keys to an existing install use the add-env-file command:
```
./manage-ohb-docker.sh add-env-file
./manage-ohb-docker.sh restart
```






