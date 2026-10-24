using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace ClubFunctions;

public sealed class ProjectPingFunction
{
    [Function("ProjectPing")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(
            AuthorizationLevel.Function,
            "get",
            Route = "projects/ping")] HttpRequestData request)
    {
        var response = request.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new { message = "Club API ready" });
        return response;
    }
}
