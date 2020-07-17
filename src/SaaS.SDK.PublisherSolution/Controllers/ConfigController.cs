namespace SaaS.SDK.PublisherSolution.Controllers {
    using System;
    using System.Collections.Generic;
    using System.Linq;
    using System.Threading.Tasks;

    using Microsoft.AspNetCore.Mvc;
    using Microsoft.Extensions.Logging;
    using Microsoft.Marketplace.SaaS.SDK.Services.Utilities;
    using Microsoft.Marketplace.Saas.Web.Controllers;
    using Microsoft.Marketplace.SaasKit.Client.DataAccess.Contracts;
    using Microsoft.Marketplace.SaasKit.Client.DataAccess.Entities;

    [ServiceFilter(typeof(KnownUserAttribute))]
    public class ConfigController : BaseController {
        readonly IApplicationConfigRepository configRepository;
        readonly ILogger<ConfigController> logger;
        public ConfigController(IApplicationConfigRepository configRepository, ILogger<ConfigController> logger) {
            this.configRepository = configRepository;
            this.logger = logger;
        }

        public IActionResult Index() {
            this.logger.LogInformation("Config Controller / Index");
            try {
                var configSettings = this.configRepository.GetAll().ToList();
                return this.View(configSettings);
            } catch (Exception ex) {
                this.logger.LogError(ex, ex.Message);
                return this.View("Error", ex);
            }
        }

        [HttpPost]
        public IActionResult UpdateSettings(List<ApplicationConfiguration> settings) {
            foreach (var update in settings) {
                this.configRepository.SetValueById(update.Id, update.Value);
            }

            return this.RedirectToAction("Index");
        }
    }
}
