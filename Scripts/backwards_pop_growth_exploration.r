# This is a script to estimate population history over time currently using logistic or exponential growth models
library(tidyverse)
options(scipen = 999)
# Load the backwards projection via github
fun <- c("https://raw.githubusercontent.com/Dave-Keith/ICM/master/Scripts/functions/backwards_project.r")
# Now run through a quick loop to load each one, just be sure that your working directory is read/write!
download.file(fun,destfile = basename(fun))
source(paste0(getwd(),"/",basename(fun)))
file.remove(paste0(getwd(),"/",basename(fun)))

# OK, so lets compare trajectories of the backwards logistic and backwards exponential
# Play around with pop.next r, and K, most interesting.  Note that if K <= our the value we start at (i.e. the most recent year) 
# we end up in some weird scenarios (if we are = K it's deterministic so we don't go anywhere (r effectively = 0), 
# and if we are above K, unless you really crank R up (to get into 'chaos' territory), the backwards calculation will 
# say that the population is > K for the whole time series, because the logistic with low r above K, just 
# declines to K smoothly
# If tossed these being deterministic and added some noise we could get some more entertaining results.

years <- 1980:2020
n.years <- length(years)
pop.next <- 40000
K = 42000
r=0.1
eff = 0.0001 # Proportional removals.
res <- data.frame(year = years, 
                  exponential = c(rep(NA,n.years-1),pop.next),
                  exp.change = c(rep(NA,n.years)),
                  rem.exp = c(rep(NA,n.years)),
                  F.exp = c(rep(NA,n.years)), # The calc below isn't quite right as it assumes the fishery happens at the end of year... but it's just for exploratory purposes...
                  logistic = c(rep(NA,n.years-1),pop.next),
                  logistic.change =  c(rep(NA,n.years)), 
                  rem.log = c(rep(NA,n.years)),
                  F.log = c(rep(NA,n.years)) # The calc below isn't quite right as it assumes the fishery happens at the end of year... but it's just for exploratory purposes...
                  )

# So a really interesting problem for back calculation of the logistic model.  As you approach K, r becomes increasingly small
# so if you 'start' the model anywhere near enough to K then you are going to have very little growth.  Buuut if you have removals
# that are higher than the growth, because we are going 'backwards' that means the population was larger last year than it was this year
# so what happens in the logistic model is that the backwards trajectory suggests that the biomass was higher in the past
# and in short order the biomass estimate is bizzaro high.  Basically if you are within N = 0.8K and F > 0.5r the logistic is going to go off
# into weird space (and probably not work) rather quickly.

# Meanwhile, if you F is similar to R the models also behave very differently than you might expect.
# If F << r then you get nice clean exponential and (sometimes) logistic growth (depending on how close K is to N), which makes sense since F is low relative to R
# If F is close to r then you get patterns that do not at all resemble logistic or exponential growth (which is good!)
# If F >> r, the models start to look like exponential decline to current stock levels cause, well you are overfishing them. But the logistic model
# is especially sensistive here and can really go into bizarro population sizes quickly.  Worth noting that even with a very high K
# the logistic model and the exponential models can end up in very different places

for(i in n.years:2)
{
  if(i == n.years) removal.log = rlnorm(1,log(eff*pop.next),sd=0.1)
  if(i == n.years) removal.exp = rlnorm(1,log(eff*pop.next),sd=0.1)
  if(i < n.years) removal.log = rlnorm(1,log(eff*pop.log.next),sd=0.1)
  if(i < n.years) removal.exp = rlnorm(1,log(eff*pop.exp.next),sd=0.1)
  
  # Start with the exponential model
  if(i != n.years) pop.next = pop.exp.next
  res$F.exp[i] <- removal.exp/ pop.next
  exp.res <- back.proj(option = "exponential",pop.next = pop.next,K=K,r=r,removals = removal.exp,fishery.timing = 'beginning')
  pop.exp.next <- exp.res$Pop.current
  res$exponential[i-1] <- pop.exp.next
  res$rem.exp[i] <- -removal.exp
  res$exp.change[i] <-  res$exponential[i] -  res$exponential[i-1] - res$rem.exp[i]
  # Run backwards through the logistic model
  if(i != n.years) pop.next = pop.log.next
  res$F.log[i] <- removal.log/ pop.next
  log.res <- back.proj(option = "logistic",pop.next = pop.next,K=K,r=r,removals = removal.log,fishery.timing = 'beginning')
  pop.log.next <- min(log.res$Pop.current)
  res$logistic[i-1] <- pop.log.next
  res$rem.log[i] <- -removal.log
  res$logistic.change[i] <- res$logistic[i] -  res$logistic[i-1] - res$rem.log[i]

}
res

res.long <- pivot_longer(res,cols =c('logistic','exponential'),names_to = "Model",values_to = "Abundance")
# Interesting how an F of even 5% seems to obliterate the shape of the logistic curve and makes the logistic model just look like an exponential model
# I haven't wrapped my head around what that is...
ggplot(res.long) + geom_line(aes(x=year,y=Abundance,color=Model),size=2) + scale_color_manual(values = c("blue","orange"))

## FOR THE FORWARD PROJECTIONS
# The forward projection solution is easy as pie so this is good, save this for when I get to the forward projections
#N.next <- (exp(r)* ((N.last)/(1-(N.last/K)))) / (1 + ( ((N.last)/(1-(N.last/K)))*exp(r))/K)



