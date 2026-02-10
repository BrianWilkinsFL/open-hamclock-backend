# Run OHB in a docker container

We always recommend using one of the cloud-based backends. There is load created on the many services hamclock uses to populate it's data. The OHB caches that data and serves it up to the many hamclock deployments.

But if you want to run your own OHB (for example you are an early adopter and don't want to wait for the cloud-based backends to be deployed), then install your own OHB.

Of course OHB can be deployed on a host OS. But there are many distributions out there and potentially the OHB dependencies can cause issues with your system. The generally accepted method of managing this is to run the service in a container.

You haven't used docker before? Now's your chance! It's not hard and it's great experience.

## What's a docker deployment?

To get OHB to run in docker on your machine, you'll need to:
- install docker on your machine (some distributions like Ubuntu 24.04 install very old docker so you might need to set up the docker repository)
- get the source tree so you can make a docker-compose file
- launch the container with the script from the source tree

## Where are the docker images?

We maintain docker images for the releases in Docker Hub. When you launch your container it will automatically pull the image from Docker Hub. If you built the image yourself (with the build scripts), it will automatically use yours.

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

Get the source tree from GitHub. The git clone command below should have the right URL but you can check it by visiting https://github.com/BrianWilkinsFL/open-hamclock-backend, click on the green "Code" button and copy the https url.

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
git checkout 1.0
```

Create a docker compose file:
```
# the help outputs options
./build-image.sh -h
# create the compose file
./build-image.sh -c
```

The output of the last command will tell you the following. If it's your first time running OHB, you'll need to create the storage space for it:
```
./docker-ohb-setup.sh
```

Finally, start it!
```
docker compose up -d
```

If it's the first time you've run it, it can take a while to populate the data. Nearly all of the current data should be ready in around 60 minutes depending on internet speed. In some cases history has to accumulate for all the graphs to look right which could take days. But while you wait days, you'll have a fully functioning hamclock with your own custom OHB.

Go to the project readme and look for information about the '-b' otion to hamclock. This will make your hamclock pull from your OHB.

# Install OHB with your own image
## The steps if you want to create your own image
The steps to create your own image are almost exactly the same as using the official image. The difference is when runing the build-image.sh script, don't pass it '-c'. The '-c' option means create only the docker-compose file. If you remove that option, it will do the full image creation:
```
./build-image.sh
```
Optionally you can pass it the -p option to customize the port or run -c later with the -p option to change it. The port is not in the image, it's in the compose file.

You still need to clone the git respository, pick out your preferred branch or release, do the setup (if it's your first time) and docker compose up. So basically follow the steps in the last section except leave out '-c'.

## Other options
In some cases port 80 might not be available on your OHB server. You can customize the port using the -p option. In the steps above, create the compose file again providing the -p option with your preferred port and run the docker compose up command again.

# Upgrades
Upgrading OHB is easy. Basically run all the steps above again. You don't need to run docker-ohb-setup.sh but it won't hurt if you do.

The data is persisted in the storage space you created in the first install. It will have the history after you upgrade. If there are new features, possibly those could take a while to populate. It just depends on the feature.

# Your hamclock
Ok, so you have a back end. But does your hamclock know about it? Go to the project readme and look for information about the '-b' otion to hamclock.






