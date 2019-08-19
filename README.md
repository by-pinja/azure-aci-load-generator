# Azure ACI load generator

It is common issue that in other hand load testing can give great value
and in other hand it's often very expensive and time consuming to setup.
This repository tries to solve that issue in generic way by using Azure
container instances to spawn large array of load generators running in
containers.

Anything that can be ran on containers can be used as load generator. For
example Selenium, JMeter, k6s.io, Puppeteer or Cypress.

Usually easiest way to generate more or less realistic load to system is
via user interface. However tools like selenium are slow and require lots
of resources since they run browser on background. This problem can be
worked around to spawn a lot of concurrent instances in ACI.

If you spawn array for longer period of time, this tool can be also be used
to generate data to target instance. Commonly issues starts to arise when
theres enough data in system.

## Setup environment and depencies

todo

## Example

todo

## Results

This tool doesn't give any advice or specifics how to monitor behavior or
speed of application under test. However you anyway have some kind of
insights/metrics for your UI which can be used together with this tool.

Just spawn load generator array and monitor how well software handles load.

One example is to use Azure Application insights to monitor UI speed and behavior
during tests. Many tools have monitoring tools for speed built in like in JMeter
or k6s.io, however collecting results that way is left to built to container and is out
of scope of this repository.
