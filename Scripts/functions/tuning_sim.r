# Here we take the ideas from the backwards projections but 'tune' them to the 'known' biomass by adjusting either the fecundity or survivorship variables iteratively until
# the biomass in the current year is withing X% of the actual biomass.

# All the data you need to make it dance...
# years:          The years you are running the backwards calculation for
# abund.ts:       The abundance time series from the assessment
# tune.par:       How close to the assessment biomass do we want to get.  default is 0.01 (1%)
# tuner:          What are we tuning, the fecundity "f", or natural mortality 'm', or both 'b'
# rems            Removals from the fishery in a given year.
# n.steps         The number of different m or f options to explore.  Make sure this is an even number!

# mat.age         Age at maturity if one value it is the age at 50% maturity, if a vector it is the age at maturities for each age(or age/year), if a matrix we want this to be unique for each simulation
#                 we could also let this vary by year, but we'll need to go 3-D array or something for that# ages:           What are the ages you are using this is used to calculate max age, which may not be ideal with plus group stocks.

# nm:             Natural mortality, this wants the instantaneous natural mortality, not the proportional. There are several options here....
#                 You can enter a vector of instantaneous natural moralities, just put a single number of all ages, or put in a character
#                 string that will tell the function to calculate the natural mortality based on life history data. If a matrix the rows are different simulations
#                 we could also let this vary by year, but we'll need to go 3-D array or something for that

# sel             The selectivity of the stock.  Currently this is set up as a single number and it is tweaked in the code, we'll need to make this more complex.


# N               Population size in a given year

# u:              Exploitation rate (annual not instantaneous), currently set up to be 1 value.

# pop.model:      What method you going to use to get the population growth modeled for the backwards model.  You can use exponential model, logistic model, 
                  #or a dec.rate (decline rate) model.

# What we need for the Lotka.r function...
# fecund:      How are you estimating fecundity. If a vector it is the number of recruits produced by the average individual in the age classes. 
#              If a matrix the rows are different simulations. Also have options to set fecund = 'eggs' which we can use if we can get an estimate of egg mortality
#              fecund = 'SPR' uses the spawner per recruit metric, to get this to work we need to know how many recruits there are in a given year
#              We could also let this vary by year, but we'll need to go 3-D array or something for that
# mat.ogive.K 
# L.inf 
# K 
# t0 
# a.len.wgt 
# b.len.wgt 
# a.fec.len 

# w.age           The weight of individuals for each age, if a matrix the rows are different simulations
#                 we could also let this vary by year, but we'll need to go 3-D array or something for that
# K
# dec.rate


tune.sim<-function(years,tune.par=0.01,tuner="m", n.steps = 30,
                   mat.age = NULL,nm=NULL,w.age = NULL,ages =NULL,fecund = NULL,N.end = NULL,abund.ts = NULL,
                   sel,rems,N,u,pop.model = "exp",
                   dec.rate = NULL,
                   L.inf = NULL,K = NULL,t0 = NULL, a.len.wgt = NULL, b.len.wgt = NULL, a.fec.len = NULL, b.fec.len = NULL,
                   sd.mat = 0,sd.nm = 0,sd.wt = 0,sd.fecund = 0)
{
  # Download the function to go from inla to sf
  funs <- c("https://raw.githubusercontent.com/freyakeyser/ICM/main/Scripts/functions/Lotka_r.r",
            "https://raw.githubusercontent.com/freyakeyser/ICM/main/Scripts/functions/backwards_project.r"
  )
  # Now run through a quick loop to load each one, just be sure that your working directory is read/write!
  for(fun in funs) 
  {
    download.file(fun,destfile = basename(fun))
    source(paste0(getwd(),"/",basename(fun)))
    file.remove(paste0(getwd(),"/",basename(fun)))
  }
  
  source("D:/Github/ICM/Scripts/functions/Lotka_r.r")
  
  
  require(optimx)  || stop("Please load the 'optimx' package which you'll need for the optimations to run")
  
  #Initialize a bunch of objects
  n.years<-length(years)
  #Pop<-data.frame(abund = rep(NA,n.years*n.sims),sim = rep(1:n.sims,n.years),years = sort(rep(years,n.sims)))    #matrix(data=NA, nrow=<<see below>>, ncol=<<see below>>,byrow=F, dimnames=NULL) 
  Pop.vec<-rep(NA,n.years)
  rem<-rep(NA,n.years)
  r.vec<-NULL
  #B1.vec<-rep(0,n.sims) ### backwards projections 
  #rems<-matrix(rep(0,n.years*n.sims),n.sims,n.years)

  # So I think what I want to create here is a big list of natural mortality and fecundity 'scenarios' that we select from until we find one that 'works'
  
  if(tuner == 'm')
  {
    nm.lst <- NULL
    for(y in 1:n.years)
    {
      # let's just make X steps around the mean either way, changing m by 5% every time....
      nm.vary <- NULL
      count <- 0
      for(s in (n.steps/2):1) 
      {
       count <- count + 1
       if(s == n.steps/2) nm.vary[[s]] <- nm[y,]
       if(s < n.steps/2) nm.vary[[s]] <- nm.vary[[s+1]]/1.05

      }
      for(s in ((n.steps/2)+1):n.steps) nm.vary[[s]] <- nm[y,]*(1+ (0.05*(s-n.steps/2)))
      nm.vary <- do.call('rbind',nm.vary)
      # Then bundle this up into a new nm.lst object we'll use later
      nm.lst[[as.character(years[y])]] <- nm.vary
    }
  }
  browser()
  
  #Calculate r for your examples... going to be a lot of lotka.r's all of a sudden isn't there...
  tmp.y <- NULL
  for(y in 1:n.years)
  {
    nm.tmp <- nm.lst[[as.character(years[y])]] 
    mat.tmp <- mat.age[y,]
    waa.tmp <- w.age[y,]
    fecund.tmp <- fecund[y,]
    tmp.s <- NULL
    
    for(ss in 1:n.steps)
    { 
      junk<-lotka.r(yrs = years[y],age.mat = mat.tmp,nat.mort = nm.tmp[ss,],ages=ages,wt.at.age=waa.tmp,fecund=fecund.tmp,
                    L.inf = L.inf,K = K,t0 = t0, 
                    a.len.wgt = a.len.wgt, b.len.wgt = b.len.wgt, 
                    a.fec.len = a.fec.len, b.fec.len = b.fec.len,
                    sd.mat = 0,sd.nm = 0,sd.wt = 0,sd.fecund = 0)
    tmp.s[[ss]] <- data.frame(year = years[y],r = junk$res[1,2],mn.m = mean(as.numeric(nm.tmp[ss,]),na.rm=T),s=ss)      
    } # end for(s in 1:30)

    tmp.y[[as.character(years[y])]] <- do.call('rbind',tmp.s)
  }

  #unwrap your r vector
  r.vec <- do.call('rbind',tmp.y)
  #browser()
   #temp.r.vec<-r.vec[r.vec>0 & r.vec<r.cutoff]
  #r.vec<-temp.r.vec[1:n.sims]
  ############################################################
  

  # Get the final year estimate of your population      
  pop.next <- rep(N.end,n.steps) # Assuming this is our known starting point, could add uncertainty to this as well if we want to.
  #r.tmp <- r.vec[r.vec$n.sims == i,]
  #Now run your model backwards with the r from the Lotka function and
  # if you use the logistic growth model the K estimated for the population.
  res <- NULL
  for(y in n.years:2)
  {
      # DK Note: So for our removals time series, we put the removals between t+1 and t 
      # down as year t+1.  We can change this, but that's how this is set up at the moment.
      removals.next <- rems[y-1]
      #browser()
      # So what I want to build here is the simulation where we test each of the s values sequentially
      # then pick the one that best fits the data.
  
      
      for(ss in 1:n.steps)
      {
        # Need to think here
        r.up <- r.vec %>% dplyr::filter(s == ss, year == years[y]) %>% dplyr::pull(r) # Grab the correct value of r
    
        # The exponential model
        if(pop.model == 'exponential') 
        {
          exp.res <- back.proj(option = "exponential",pop.next = pop.next[ss],r=r.up,removals = removals.next)
          pop.next[ss] <- exp.res$Pop.current
          
        }
        # If you are running the logistic model
        if(pop.model == 'logistic')
        {
          log.res <- back.proj(option = "logistic",pop.next = pop.next[ss],K=K,r=r.up,removals = removals.next)
          pop.next <- min(log.res$Pop.current)
        }
        if(pop.model == 'dec.rate')
        {
          # This needs way more thought than it's been given by DK!
          #removals[i,]<-(-1+exp(r.vec[i])+dec.rate[i]) ## redone with Jamie.
          pop.next[ss] <- pop.next[ss] + pop.next[ss]*(-1+exp(r.up)+dec.rate[i])
        } # Looping through the s scenarios for a year
        # So here we need to pick the best of the pop.next's based on the bm.est.
        #browser()
        r.vec$vpa.m[r.vec$s == ss & r.vec$year == years[y]] <- mean(as.numeric(nm[y,]),na.rm=T)
        r.vec$vpa.n[r.vec$s == ss & r.vec$year == years[y]] <- abund.ts[y-1]
        r.vec$lotka.n[r.vec$s == ss & r.vec$year == years[y]] <- pop.next[ss]
        r.vec$diff.n[r.vec$s == ss & r.vec$year == years[y]] <- pop.next[ss] - abund.ts[y-1]
        r.vec$per.diff.n[r.vec$s == ss & r.vec$year == years[y]] <- 100*((pop.next[ss] - abund.ts[y-1])/abund.ts[y-1])
        # Then we find the minimum and that becomes or model of choice and we've retained the summary of the natural mortality from that simulation
        
      }
      # Now we chose the 'best' r.vec and use that for the next year population
      #browser()
      r.tmp <- r.vec[r.vec$year == years[y],]
      min.dif <- min(abs(r.tmp$diff.n),na.rm=T)
      keep <- which(abs(r.tmp$diff.n) == min.dif)
      
      res[[y]] <- r.tmp[keep,]
      pop.next <- rep(res[[y]]$lotka.n,n.steps)
      
    } #Loop through all the years.
    res.final <- do.call('rbind',res)
    res.final$diff.m <- res.final$mn.m - res.final$vpa.m
    res.final$per.diff.m <- 100*((res.final$mn.m - res.final$vpa.m)/res.final$vpa.m)


    return(list(res=res.final))
}
  
  